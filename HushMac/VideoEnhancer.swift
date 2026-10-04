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
    private let blit: MTLRenderPipelineState
    private var textureCache: CVMetalTextureCache?
    private var scaler: (any MTLFXSpatialScaler)?
    private var scalerKey: (Int, Int, Int, Int)?
    private var scalerFailedKey: (Int, Int, Int, Int)?
    private var rgb: MTLTexture?
    private var upscaled: MTLTexture?
    private let sampler: MTLSamplerState

    /// 0…1. Kept subtle.
    var sharpness: Float = 0.3

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue(),
              MTLFXSpatialScalerDescriptor.supportsDevice(device) else { return nil }
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            guard let convertFunction = library.makeFunction(name: "hushYCbCrToRGB"),
                  let vertex = library.makeFunction(name: "hushBlitVertex"),
                  let fragment = library.makeFunction(name: "hushBlitFragment") else { return nil }
            convert = try device.makeComputePipelineState(function: convertFunction)
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
    /// the target's edges for Fill and Zoom). Only the visible part of the picture is processed.
    /// Returns false if it couldn't (the caller falls back to the plain picture).
    @discardableResult
    func encode(source: CVPixelBuffer, into target: MTLTexture, displayRect: CGRect, enhance: Bool,
                commandBuffer: MTLCommandBuffer) -> Bool {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let bounds = CGRect(x: 0, y: 0, width: target.width, height: target.height)
        guard width > 0, height > 0, displayRect.width > 0, displayRect.height > 0,
              let luma = texture(source, plane: 0, format: .r8Unorm),
              let chroma = texture(source, plane: 1, format: .rg8Unorm) else { return false }

        // The visible part of the picture, in source pixels (whole pixels, so a little generous).
        let visible = displayRect.intersection(bounds)
        let perSourceX = displayRect.width / CGFloat(width)
        let perSourceY = displayRect.height / CGFloat(height)
        var crop = (x: 0, y: 0, width: width, height: height)
        if !visible.isNull {
            let x0 = max(Int(((visible.minX - displayRect.minX) / perSourceX).rounded(.down)), 0)
            let y0 = max(Int(((visible.minY - displayRect.minY) / perSourceY).rounded(.down)), 0)
            let x1 = min(Int(((visible.maxX - displayRect.minX) / perSourceX).rounded(.up)), width)
            let y1 = min(Int(((visible.maxY - displayRect.minY) / perSourceY).rounded(.up)), height)
            if x1 > x0, y1 > y0 { crop = (x0, y0, x1 - x0, y1 - y0) }
        }
        // Where that crop lands on screen.
        let cropRect = CGRect(x: displayRect.minX + CGFloat(crop.x) * perSourceX,
                              y: displayRect.minY + CGFloat(crop.y) * perSourceY,
                              width: CGFloat(crop.width) * perSourceX,
                              height: CGFloat(crop.height) * perSourceY)
        let outputWidth = Int(cropRect.width.rounded())
        let outputHeight = Int(cropRect.height.rounded())
        let enlarging = outputWidth > Int(Double(crop.width) * 1.02) && outputHeight > Int(Double(crop.height) * 1.02)

        guard let rgb = reusable(&self.rgb, width: crop.width, height: crop.height, usage: [.shaderRead, .shaderWrite]),
              let compute = commandBuffer.makeComputeCommandEncoder() else { return false }

        // 1. YCbCr (video range) → RGB for the visible crop, with the frame's own colour matrix.
        var coefficients = Self.coefficients(for: source)
        var origin = SIMD2<UInt32>(UInt32(crop.x), UInt32(crop.y))
        compute.setComputePipelineState(convert)
        compute.setTexture(luma, index: 0)
        compute.setTexture(chroma, index: 1)
        compute.setTexture(rgb, index: 2)
        compute.setBytes(&coefficients, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        compute.setBytes(&origin, length: MemoryLayout<SIMD2<UInt32>>.size, index: 1)
        compute.setSamplerState(sampler, index: 0)
        dispatch(compute, width: crop.width, height: crop.height)
        compute.endEncoding()

        // 2. Upscale to the size it's shown at (only when it's actually being enlarged).
        var shown = rgb
        var sharpenAmount: Float = 0
        if enhance, enlarging,
           let scaler = scaler(inputWidth: crop.width, inputHeight: crop.height, outputWidth: outputWidth, outputHeight: outputHeight),
           let upscaled = reusable(&self.upscaled, width: outputWidth, height: outputHeight, usage: scaler.outputTextureUsage.union([.shaderRead]), storage: .private) {
            scaler.colorTexture = rgb
            scaler.outputTexture = upscaled
            scaler.inputContentWidth = crop.width
            scaler.inputContentHeight = crop.height
            scaler.encode(commandBuffer: commandBuffer)
            shown = upscaled
            sharpenAmount = sharpness
        }

        // 3. Into the target (black around it for Fit), sharpening as it's drawn.
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let render = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        let drawn = cropRect.intersection(bounds)
        if !drawn.isNull, drawn.width >= 1, drawn.height >= 1 {
            var uniforms = BlitUniforms(
                window: SIMD4<Float>(
                    Float((drawn.minX - cropRect.minX) / cropRect.width),
                    Float((drawn.minY - cropRect.minY) / cropRect.height),
                    Float(drawn.width / cropRect.width),
                    Float(drawn.height / cropRect.height)
                ),
                texel: SIMD2<Float>(1 / Float(shown.width), 1 / Float(shown.height)),
                amount: sharpenAmount
            )
            render.setViewport(MTLViewport(originX: drawn.minX, originY: drawn.minY,
                                           width: drawn.width, height: drawn.height, znear: 0, zfar: 1))
            render.setRenderPipelineState(blit)
            render.setVertexBytes(&uniforms, length: MemoryLayout<BlitUniforms>.stride, index: 0)
            render.setFragmentBytes(&uniforms, length: MemoryLayout<BlitUniforms>.stride, index: 0)
            render.setFragmentTexture(shown, index: 0)
            render.setFragmentSamplerState(sampler, index: 0)
            render.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        render.endEncoding()
        return true
    }

    private struct BlitUniforms {
        var window: SIMD4<Float>
        var texel: SIMD2<Float>
        var amount: Float
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
                               constant uint2 &origin [[buffer(1)]],
                               sampler s [[sampler(0)]],
                               uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
        uint2 p = gid + origin;
        float2 uv = (float2(p) + 0.5) / float2(luma.get_width(), luma.get_height());
        float y = (luma.read(p).r - 16.0 / 255.0) * (255.0 / 219.0);
        float2 c = (chroma.sample(s, uv).rg - 128.0 / 255.0) * (255.0 / 224.0);
        float3 rgb = float3(y + k.x * c.y, y + k.y * c.x + k.z * c.y, y + k.w * c.x);
        output.write(float4(saturate(rgb), 1.0), gid);
    }

    struct BlitUniforms { float4 window; float2 texel; float amount; };
    struct BlitOut { float4 position [[position]]; float2 uv; };

    vertex BlitOut hushBlitVertex(uint vid [[vertex_id]], constant BlitUniforms &u [[buffer(0)]]) {
        float2 corner = float2((vid << 1) & 2, vid & 2);
        BlitOut out;
        out.position = float4(corner * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
        out.uv = u.window.xy + corner * u.window.zw;
        return out;
    }

    // Draws the picture; when enhancing, with a contrast-adaptive sharpen on brightness only:
    // strongest on soft detail, backing off near strong edges (no halos), nothing in flat areas
    // (no boosted compression noise), and never past the local min/max.
    fragment float4 hushBlitFragment(BlitOut in [[stage_in]], texture2d<float> image [[texture(0)]],
                                     sampler s [[sampler(0)]], constant BlitUniforms &u [[buffer(0)]]) {
        float3 c = image.sample(s, in.uv).rgb;
        if (u.amount <= 0.0) return float4(c, 1.0);
        const float3 toLuma = float3(0.2126, 0.7152, 0.0722);
        float lc = dot(c, toLuma);
        float ln = dot(image.sample(s, in.uv - float2(0, u.texel.y)).rgb, toLuma);
        float ls = dot(image.sample(s, in.uv + float2(0, u.texel.y)).rgb, toLuma);
        float lw = dot(image.sample(s, in.uv - float2(u.texel.x, 0)).rgb, toLuma);
        float le = dot(image.sample(s, in.uv + float2(u.texel.x, 0)).rgb, toLuma);
        float mn = min(lc, min(min(ln, ls), min(lw, le)));
        float mx = max(lc, max(max(ln, ls), max(lw, le)));
        if (mx - mn < 0.02) return float4(c, 1.0);
        float amp = sqrt(saturate(min(mn, 1.0 - mx) / max(mx, 1e-4)));
        float weight = -amp * mix(0.125, 0.2, saturate(u.amount));
        float sharp = clamp((lc + weight * (ln + ls + lw + le)) / (1.0 + 4.0 * weight), mn, mx);
        return float4(saturate(c + (sharp - lc)), 1.0);
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
