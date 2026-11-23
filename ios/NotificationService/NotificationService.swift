import UserNotifications

/// Shows the picture of a push on iOS (the story cover, an animated GIF).
///
/// The API sends the picture URL in `apns.fcm_options.image` with
/// `mutable-content: 1`, so iOS runs this extension before showing the push.
/// It downloads the picture and attaches it; iOS then shows it when the
/// notification is expanded (a GIF animates there). If anything goes wrong,
/// or time runs out, the push is shown as it came, without the picture.
///
/// Self-contained on purpose: no Firebase pod, so the Podfile does not change.
class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?
    private var task: URLSessionDownloadTask?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        let content = request.content.mutableCopy() as? UNMutableNotificationContent
        bestAttempt = content

        guard let content = content, let url = Self.imageURL(in: content.userInfo) else {
            finish(request.content)
            return
        }

        task = URLSession.shared.downloadTask(with: url) { [weak self] location, response, _ in
            guard let self = self else { return }
            if let location = location,
               let attachment = Self.attachment(from: location, url: url, mimeType: response?.mimeType) {
                content.attachments = [attachment]
            }
            self.finish(content)
        }
        task?.resume()
    }

    /// iOS is about to stop the extension: show the push without the picture.
    override func serviceExtensionTimeWillExpire() {
        task?.cancel()
        if let content = bestAttempt {
            finish(content)
        }
    }

    /// Hands the content to iOS once, whichever path gets here first.
    private func finish(_ content: UNNotificationContent) {
        guard let handler = contentHandler else { return }
        contentHandler = nil
        handler(content)
    }

    /// `fcm_options.image` as FCM delivers it; only HTTPS is used.
    static func imageURL(in userInfo: [AnyHashable: Any]) -> URL? {
        guard let options = userInfo["fcm_options"] as? [String: Any],
              let text = options["image"] as? String,
              let url = URL(string: text),
              url.scheme?.lowercased() == "https" else {
            return nil
        }
        return url
    }

    /// Moves the download to a file with the right extension (iOS decides the
    /// type from it) and wraps it as an attachment.
    static func attachment(from location: URL, url: URL, mimeType: String?) -> UNNotificationAttachment? {
        let ext: String
        switch mimeType?.lowercased() {
        case "image/gif": ext = "gif"
        case "image/png": ext = "png"
        case "image/jpeg", "image/jpg": ext = "jpg"
        default: ext = url.pathExtension.isEmpty ? "gif" : url.pathExtension.lowercased()
        }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        do {
            try FileManager.default.moveItem(at: location, to: file)
            return try UNNotificationAttachment(identifier: "picture", url: file, options: nil)
        } catch {
            return nil
        }
    }
}
