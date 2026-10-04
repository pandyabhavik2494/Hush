import Foundation

/// Telling Apple TV purchases (movies and shows bought or rented from Apple) apart from your own
/// video files. Purchases belong to the TV app: they're copy-protected or live only in the cloud, so
/// Hush can't play them, and the Movies tab shows only your own files.
enum AppleTVPurchases {
    /// - Parameters:
    ///   - kind: The library's file kind ("Purchased MPEG-4 video file", "Protected MPEG-4 video
    ///     file"…) where the platform offers it (the Mac's iTunes library; nil on the iPhone).
    ///   - isProtected: Copy-protected (FairPlay).
    ///   - hasLocalFile: There's a file on this device Hush could open.
    ///   - isCloud: The item lives in the cloud (not downloaded).
    static func isPurchase(kind: String?, isProtected: Bool, hasLocalFile: Bool, isCloud: Bool) -> Bool {
        if isProtected || isCloud || !hasLocalFile { return true }
        guard let kind = kind?.lowercased() else { return false }
        return kind.contains("purchased") || kind.contains("protected")
    }
}
