import AppKit
import ShelfKit

/// Reads a pasteboard (a drop, the clipboard, a Services request) into shelf items.
/// Priority: real files > file promises > raw image data > web link > plain text.
enum Ingest {
    static let urlName = NSPasteboard.PasteboardType("public.url-name")
    static let jpeg = NSPasteboard.PasteboardType("public.jpeg")

    /// Types the shelf registers for as a drop destination.
    static var acceptedTypes: [NSPasteboard.PasteboardType] {
        [.fileURL, .URL, .string, .png, .tiff, jpeg]
            + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    }

    /// `completion` is always called on main, possibly asynchronously (file promises).
    static func read(_ pb: NSPasteboard, factory: ItemFactory, allowPromises: Bool = true,
                     completion: @escaping ([ShelfItem]) -> Void) {
        // 1. Files on disk.
        let fileURLs = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !fileURLs.isEmpty, let item = factory.files(fileURLs) {
            completion([item]); return
        }

        // 2. File promises (Mail attachments, Photos, browser images, screenshots thumbnail).
        if allowPromises,
           let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
           !receivers.isEmpty, let dir = factory.makeDropDirectory() {
            receive(receivers, into: dir) { urls in
                if let item = factory.ownedFiles(urls) {
                    completion([item])
                } else {
                    try? FileManager.default.removeItem(at: dir)
                    // Promise failed: fall back to whatever else the pasteboard carries.
                    read(pb, factory: factory, allowPromises: false, completion: completion)
                }
            }
            return
        }

        // 3. Raw image data.
        if let type = pb.availableType(from: [.png, jpeg, .tiff]), let data = pb.data(forType: type) {
            var bytes = data, ext = type == jpeg ? "jpg" : "png"
            if type == .tiff {
                if let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) {
                    bytes = png
                } else { ext = "tiff" }
            }
            if let item = factory.image(bytes, ext: ext) { completion([item]); return }
        }

        // 4. Web link.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let web = urls.first(where: { !$0.isFileURL }),
           let item = factory.link(web, title: pb.string(forType: urlName)) {
            completion([item]); return
        }

        // 5. Text (a bare URL becomes a link).
        if let s = pb.string(forType: .string) {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.contains(where: \.isWhitespace), let u = URL(string: trimmed),
               let scheme = u.scheme?.lowercased(), ["http", "https"].contains(scheme), u.host != nil,
               let item = factory.link(u) {
                completion([item]); return
            }
            if let item = factory.text(s) { completion([item]); return }
        }
        completion([])
    }

    private static let promiseQueue: OperationQueue = {
        let q = OperationQueue()
        q.qualityOfService = .userInitiated
        return q
    }()

    private static func receive(_ receivers: [NSFilePromiseReceiver], into dir: URL,
                                done: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        var finished = false
        for r in receivers {
            let expected = max(r.fileTypes.count, 1)
            var remaining = expected
            for _ in 0..<expected { group.enter() }
            r.receivePromisedFiles(atDestination: dir, options: [:], operationQueue: promiseQueue) { url, error in
                lock.lock()
                if error == nil { urls.append(url) }
                let leave = remaining > 0
                if leave { remaining -= 1 }
                lock.unlock()
                if leave { group.leave() }
            }
        }
        let finish = {
            guard !finished else { return }
            finished = true
            lock.lock(); let got = urls; lock.unlock()
            done(got)
        }
        group.notify(queue: .main, execute: finish)
        // Some apps never call back for every promised type; don't hang forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: finish)
    }
}
