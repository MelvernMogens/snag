import AppKit
import QuickLookThumbnailing

/// QuickLook thumbnails with an icon fallback, cached by path + modification date.
final class Thumbnails {
    static let shared = Thumbnails()
    private let cache = NSCache<NSString, NSImage>()

    private func key(_ url: URL, _ size: CGSize) -> NSString {
        let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
            .timeIntervalSince1970 ?? 0
        return "\(url.path)|\(mod)|\(Int(size.width))" as NSString
    }

    /// Returns the best image available right now (cached thumbnail or the file icon) and,
    /// if a real thumbnail still has to be generated, calls `update` on main when it arrives.
    func image(for url: URL, size: CGSize, update: @escaping (NSImage) -> Void) -> NSImage {
        let k = key(url, size)
        if let hit = cache.object(forKey: k) { return hit }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = size
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let req = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            guard let rep else { return }
            let img = rep.nsImage
            DispatchQueue.main.async {
                self?.cache.setObject(img, forKey: k)
                update(img)
            }
        }
        return icon
    }

    func invalidate() { cache.removeAllObjects() }
}
