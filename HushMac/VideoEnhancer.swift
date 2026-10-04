import AVFoundation
import CoreVideo
import Metal
import MetalFX
import os
import VideoToolbox

/// Picture enhancement for the video player: each frame is upscaled to its real size on screen with
/// MetalFX (instead of a plain stretch), then given a light, contrast-adaptive sharpen on brightness
/// only — no halos, nothing added in flat areas where compression noise lives, no colour shift.
/// Small videos (up to 960×960, macOS 26) first go through VideoToolbox's real-time super
/// resolution at 2×. Anything that fails just means the plain picture.
final class VideoEnhancer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    private let convert: MTLComputePipelineState
    private let sharpen: MTLComputePipelineState
    private let blit: MTLRenderPipelineState
    private var textureCache: CVMetalTextureCache?
    private var scaler: (any MTLFXSpatialScaler)?
    private var scalerKey: (Int, Int, Int, Int)?
    private var scalerFailedKey: (Int, Int, Int, Int)?
    private var rgb: MTLTexture?
    private var upscaled: MTLTexture?
    private var sharpened: MTLTexture?
    private let sampler: MTLSamplerState

    /// 0…1. Kept subtle.
    var sharpness: Float = 0.3

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue(),
              MTLFXSpatialScalerDescriptor.supportsDevice(device) else { return nil }
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            guard let convertFunction = library.makeFunction(name: "hushYCbCrToRGB"),
                  let sharpenFunction = library.makeFunction(name: "hushSharpen"),
                  let vertex = library.makeFunction(name: "hushBlitVertex"),
                  let fragment = library.makeFunction(name: "hushBlitFragment") else { return nil }
            convert = try device.makeComputePipelineState(function: convertFunction)
            sharpen = try device.makeComputePipelineState(function: sharpenFunction)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            blit = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            hushLog.error("Enhance: shaders failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else { return nil }
        self.sampler = sampler
        self.device = device
        self.queue = queue
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        guard textureCache != nil else { return nil }
    }

    /// Pixel buffer attributes for the frames the enhancer reads (what the real-time super
    /// resolution needs too): 4:2:0 video range, IOSurface-backed, Metal-compatible.
    static let pixelBufferAttributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelBufferMetalCompatibilityKey as String: true,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
    ]

    /// Draws `source` into `target`, filling `displayRect` (in the target's pixels; it may reach past
    /// the target's edges for Fill and Zoom). Returns false if it couldn't (the caller falls back).
    @discardableResult
    func encode(source: CVPixelBuffer, into target: MTLTexture, displayRect: CGRect, enhance: Bool,
                commandBuffer: MTLCommandBuffer) -> Bool {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        guard width > 0, height > 0, displayRect.width > 0, displayRect.height > 0,
              let luma = texture(source, plane: 0, format: .r8Unorm),
              let chroma = texture(source, plane: 1, format: .rg8Unorm),
              let rgb = reusable(&self.rgb, width: width, height: height, usage: [.shaderRead, .shaderWrite]),
              let compute = commandBuffer.makeComputeCommandEncoder() else { return false }

        // 1. YCbCr (video range) → RGB, with the frame's own colour matrix.
        var coefficients = Self.coefficients(for: source)
        compute.setComputePipelineState(convert)
        compute.setTexture(luma, index: 0)
        compute.setTexture(chroma, index: 1)
        compute.setTexture(rgb, index: 2)
        compute.setBytes(&coefficients, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        compute.setSamplerState(sampler, index: 0)
        dispatch(compute, width: width, height: height)
        compute.endEncoding()

        var shown = rgb
        let outputWidth = Int(displayRect.width.rounded())
        let outputHeight = Int(displayRect.height.rounded())
        // 2. Upscale to the size it's shown at, then sharpen — only when it's actually being enlarged.
        if enhance, outputWidth > Int(Double(width) * 1.02), outputHeight > Int(Double(height) * 1.02),
           let scaler = scaler(inputWidth: width, inputHeight: height, outputWidth: outputWidth, outputHeight: outputHeight),
           let upscaled = reusable(&self.upscaled, width: outputWidth, height: outputHeight, usage: scaler.outputTextureUsage.union([.shaderRead, .shaderWrite]), storage: .private),
           let sharpened = reusable(&self.sharpened, width: outputWidth, height: outputHeight, usage: [.shaderRead, .shaderWrite], storage: .private) {
            scaler.colorTexture = rgb
            scaler.outputTexture = upscaled
            scaler.inputContentWidth = width
            scaler.inputContentHeight = height
            scaler.encode(commandBuffer: commandBuffer)
            if let pass = commandBuffer.makeComputeCommandEncoder() {
                var amount = sharpness
                pass.setComputePipelineState(sharpen)
                pass.setTexture(upscaled, index: 0)
                pass.setTexture(sharpened, index: 1)
                pass.setBytes(&amount, length: MemoryLayout<Float>.size, index: 0)
                dispatch(pass, width: outputWidth, height: outputHeight)
                pass.endEncoding()
                shown = sharpened
            } else {
                shown = upscaled
            }
        }

        // 3. Into the target: black around it (Fit), cropped past the edges (Fill, Zoom).
        let bounds = CGRect(x: 0, y: 0, width: target.width, height: target.height)
        let visible = displayRect.intersection(bounds)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let render = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        if !visible.isNull, visible.width >= 1, visible.height >= 1 {
            // The part of the picture that's visible, in texture coordinates.
            var uv = SIMD4<Float>(
                Float((visible.minX - displayRect.minX) / displayRect.width),
                Float((visible.minY - displayRect.minY) / displayRect.height),
                Float(visible.width / displayRect.width),
                Float(visible.height / displayRect.height)
            )
            render.setViewport(MTLViewport(originX: visible.minX, originY: visible.minY,
                                           width: visible.width, height: visible.height, znear: 0, zfar: 1))
            render.setRenderPipelineState(blit)
            render.setVertexBytes(&uv, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
            render.setFragmentTexture(shown, index: 0)
            render.setFragmentSamplerState(sampler, index: 0)
            render.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        render.endEncoding()
        return true
    }

    // MARK: Helpers

    private func texture(_ buffer: CVPixelBuffer, plane: Int, format: MTLPixelFormat) -> MTLTexture? {
        guard let textureCache else { return nil }
        var cvTexture: CVMetalTexture?
        let width = CVPixelBufferGetWidthOfPlane(buffer, plane)
        let height = CVPixelBufferGetHeightOfPlane(buffer, plane)
        CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, buffer, nil, format, width, height, plane, &cvTexture)
        return cvTexture.flatMap(CVMetalTextureGetTexture)
    }

    private func reusable(_ slot: inout MTLTexture?, width: Int, height: Int, usage: MTLTextureUsage,
                          storage: MTLStorageMode = .private) -> MTLTexture? {
        if let existing = slot, existing.width == width, existing.height == height, existing.usage.contains(usage) { return existing }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = usage
        descriptor.storageMode = storage
        slot = device.makeTexture(descriptor: descriptor)
        return slot
    }

    private func scaler(inputWidth: Int, inputHeight: Int, outputWidth: Int, outputHeight: Int) -> (any MTLFXSpatialScaler)? {
        let key = (inputWidth, inputHeight, outputWidth, outputHeight)
        if let scalerKey, scalerKey == key, let scaler { return scaler }
        if let scalerFailedKey, scalerFailedKey == key { return nil }
        let descriptor = MTLFXSpatialScalerDescriptor()
        descriptor.inputWidth = inputWidth
        descriptor.inputHeight = inputHeight
        descriptor.outputWidth = outputWidth
        descriptor.outputHeight = outputHeight
        descriptor.colorTextureFormat = .bgra8Unorm
        descriptor.outputTextureFormat = .bgra8Unorm
        descriptor.colorProcessingMode = .perceptual
        guard let made = descriptor.makeSpatialScaler(device: device) else {
            scalerFailedKey = key
            hushLog.info("Enhance: MetalFX can't scale \(inputWidth)x\(inputHeight) to \(outputWidth)x\(outputHeight); plain picture")
            return nil
        }
        scaler = made
        scalerKey = key
        return made
    }

    private func dispatch(_ encoder: MTLComputeCommandEncoder, width: Int, height: Int) {
        let group = MTLSize(width: 16, height: 16, depth: 1)
        let grid = MTLSize(width: (width + 15) / 16, height: (height + 15) / 16, depth: 1)
        encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: group)
    }

    /// (Cr→R, Cb→G, Cr→G, Cb→B) for the frame's colour matrix: BT.709 for HD, BT.601 for SD.
    private static func coefficients(for buffer: CVPixelBuffer) -> SIMD4<Float> {
        let matrix = CVBufferCopyAttachment(buffer, kCVImageBufferYCbCrMatrixKey, nil) as? String
        let is601 = matrix.map { $0 == (kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String) || $0 == (kCVImageBufferYCbCrMatrix_SMPTE_240M_1995 as String) }
            ?? (CVPixelBufferGetHeight(buffer) < 720)
        return is601 ? SIMD4(1.402, -0.344136, -0.714136, 1.772) : SIMD4(1.5748, -0.1873, -0.4681, 1.8556)
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    kernel void hushYCbCrToRGB(texture2d<float, access::read> luma [[texture(0)]],
                               texture2d<float, access::sample> chroma [[texture(1)]],
                               texture2d<float, access::write> output [[texture(2)]],
                               constant float4 &k [[buffer(0)]],
                               sampler s [[sampler(0)]],
                               uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
        float2 uv = (float2(gid) + 0.5) / float2(output.get_width(), output.get_height());
        float y = (luma.read(gid).r - 16.0 / 255.0) * (255.0 / 219.0);
        float2 c = (chroma.sample(s, uv).rg - 128.0 / 255.0) * (255.0 / 224.0);
        float3 rgb = float3(y + k.x * c.y, y + k.y * c.x + k.z * c.y, y + k.w * c.x);
        output.write(float4(saturate(rgb), 1.0), gid);
    }

    // Contrast-adaptive sharpen on brightness only: strongest on soft detail, backing off near
    // strong edges (no halos) and doing nothing in flat areas (no boosted compression noise).
    kernel void hushSharpen(texture2d<float, access::read> input [[texture(0)]],
                            texture2d<float, access::write> output [[texture(1)]],
                            constant float &amount [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
        uint w = input.get_width(), h = input.get_height();
        if (gid.x >= w || gid.y >= h) return;
        const float3 toLuma = float3(0.2126, 0.7152, 0.0722);
        float3 c = input.read(gid).rgb;
        float lc = dot(c, toLuma);
        float ln = dot(input.read(uint2(gid.x, gid.y > 0 ? gid.y - 1 : 0)).rgb, toLuma);
        float ls = dot(input.read(uint2(gid.x, min(gid.y + 1, h - 1))).rgb, toLuma);
        float lw = dot(input.read(uint2(gid.x > 0 ? gid.x - 1 : 0, gid.y)).rgb, toLuma);
        float le = dot(input.read(uint2(min(gid.x + 1, w - 1), gid.y)).rgb, toLuma);
        float mn = min(lc, min(min(ln, ls), min(lw, le)));
        float mx = max(lc, max(max(ln, ls), max(lw, le)));
        float contrast = mx - mn;
        if (contrast < 0.02) { output.write(float4(c, 1.0), gid); return; }
        float amp = sqrt(saturate(min(mn, 1.0 - mx) / max(mx, 1e-4)));
        float weight = -amp * mix(0.125, 0.2, saturate(amount));
        float sharp = (lc + weight * (ln + ls + lw + le)) / (1.0 + 4.0 * weight);
        sharp = clamp(sharp, mn, mx);
        output.write(float4(saturate(c + (sharp - lc)), 1.0), gid);
    }

    struct BlitOut { float4 position [[position]]; float2 uv; };

    vertex BlitOut hushBlitVertex(uint vid [[vertex_id]], constant float4 &window [[buffer(0)]]) {
        float2 corner = float2((vid << 1) & 2, vid & 2);
        BlitOut out;
        out.position = float4(corner * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
        out.uv = window.xy + corner * window.zw;
        return out;
    }

    fragment float4 hushBlitFragment(BlitOut in [[stage_in]], texture2d<float> image [[texture(0)]], sampler s [[sampler(0)]]) {
        return float4(image.sample(s, in.uv).rgb, 1.0);
    }
    """
}

/// A pixel buffer handed from the frame processor's completion to the main thread. CVPixelBuffer
/// isn't marked Sendable, but ownership passes to a single consumer and nobody else touches the
/// buffer after it's handed over, so crossing threads here is safe.
struct HandedOffPixelBuffer: @unchecked Sendable {
    let buffer: CVPixelBuffer?
}

// MARK: - Real-time super resolution (small videos, macOS 26)

/// VideoToolbox's low-latency super resolution at 2×, for videos up to 960×960. The session starts
/// in the background (loading the model can take longer than a frame); until it's ready, or if it
/// ever fails, frames pass through untouched.
@available(macOS 26.0, *)
final class RealTimeSuperResolution: @unchecked Sendable {
    let inputWidth: Int
    let inputHeight: Int
    private let processor = VTFrameProcessor()
    private var pool: CVPixelBufferPool?
    private let lock = NSLock()
    private var ready = false
    private var failed = false

    static func supports(width: Int, height: Int) -> Bool {
        guard VTLowLatencySuperResolutionScalerConfiguration.isSupported else { return false }
        let factors = VTLowLatencySuperResolutionScalerConfiguration.__supportedScaleFactors(forFrameWidth: width, frameHeight: height)
        return factors.contains { $0.floatValue == 2 }
    }

    init(width: Int, height: Int) {
        inputWidth = width
        inputHeight = height
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let configuration = VTLowLatencySuperResolutionScalerConfiguration(frameWidth: width, frameHeight: height, scaleFactor: 2)
            var poolOut: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, configuration.destinationPixelBufferAttributes as CFDictionary, &poolOut)
            do {
                try processor.startSession(configuration: configuration)
                lock.withLock {
                    pool = poolOut
                    ready = poolOut != nil
                }
                hushLog.info("Enhance: real-time super resolution ready for \(width)x\(height)")
            } catch {
                lock.withLock { failed = true }
                hushLog.info("Enhance: real-time super resolution unavailable: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    var isReady: Bool { lock.withLock { ready && !failed } }

    /// Upscales one frame (asynchronously); nil if it couldn't.
    func process(_ buffer: CVPixelBuffer, time: CMTime, completion: @escaping @Sendable (HandedOffPixelBuffer) -> Void) {
        let pool: CVPixelBufferPool? = lock.withLock { ready && !failed ? self.pool : nil }
        var output: CVPixelBuffer?
        guard let pool, CVPixelBufferGetWidth(buffer) == inputWidth, CVPixelBufferGetHeight(buffer) == inputHeight,
              CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output) == kCVReturnSuccess, let output,
              let source = VTFrameProcessorFrame(buffer: buffer, presentationTimeStamp: time),
              let destination = VTFrameProcessorFrame(buffer: output, presentationTimeStamp: time) else {
            completion(HandedOffPixelBuffer(buffer: nil))
            return
        }
        // The upscaled frame keeps the source's colour tags.
        CVBufferPropagateAttachments(buffer, output)
        let parameters = VTLowLatencySuperResolutionScalerParameters(sourceFrame: source, destinationFrame: destination)
        processor.process(parameters: parameters) { [weak self] _, error in
            if error != nil {
                self?.lock.withLock { self?.failed = true }
                completion(HandedOffPixelBuffer(buffer: nil))
            } else {
                completion(HandedOffPixelBuffer(buffer: output))
            }
        }
    }

    deinit {
        processor.endSession()
    }
}
