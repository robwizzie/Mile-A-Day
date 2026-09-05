//
//  NotificationService.swift
//  MileADayNotificationService
//
//  Created by Rob Wiscount on 9/4/26.
//
//  Attaches the post's photo (or its route card) to a push banner, the way
//  Instagram puts the liked picture on a like notification.
//
//  This runs in its OWN PROCESS with no session, no keychain and no API base.
//  It cannot ask the app for anything and it cannot authenticate, so the only
//  url it can use is the absolute, pre-signed one the server puts in
//  `data.image_url` (hypeController.hypePushImageURL). Anything else — a
//  relative path, a protected endpoint — silently produces a plain banner.
//
//  Everything here degrades to the un-decorated notification. A push that
//  arrives without a picture is the push we shipped before this target
//  existed; a push that never arrives because the extension crashed or ran
//  out of time is a regression. That asymmetry drives every decision below.
//

import UniformTypeIdentifiers
import UserNotifications

class NotificationService: UNNotificationServiceExtension {

    /// iOS gives an extension roughly 30s. We deliberately spend far less: the
    /// banner is worth showing on time even without its picture, so the fetch
    /// gets a short leash and `serviceExtensionTimeWillExpire` is a backstop,
    /// not the plan.
    private static let fetchTimeout: TimeInterval = 8

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?
    private var task: URLSessionDataTask?
    private let lock = NSLock()

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        let content = request.content.mutableCopy() as? UNMutableNotificationContent
        bestAttemptContent = content

        guard
            let content,
            let url = Self.imageURL(in: request.content.userInfo)
        else {
            contentHandler(request.content)
            return
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Self.fetchTimeout
        config.timeoutIntervalForResource = Self.fetchTimeout

        task = URLSession(configuration: config).dataTask(with: url) {
            [weak self] data, response, _ in
            guard let self else { return }
            defer { self.deliver() }
            guard
                let data,
                !data.isEmpty,
                (response as? HTTPURLResponse)?.statusCode == 200,
                let attachment = Self.attachment(for: data, from: url)
            else { return }
            content.attachments = [attachment]
        }
        task?.resume()
    }

    override func serviceExtensionTimeWillExpire() {
        // Out of time: ship the banner as-is rather than letting iOS drop it.
        task?.cancel()
        deliver()
    }

    /// Hands the content back EXACTLY once.
    ///
    /// Both the URLSession completion and `serviceExtensionTimeWillExpire` can
    /// reach here — a cancelled request still calls its completion — and they
    /// arrive on different threads, so the handler is consumed under a lock.
    /// Calling it twice is undefined behaviour; not calling it drops the
    /// notification entirely.
    private func deliver() {
        lock.lock()
        let handler = contentHandler
        let content = bestAttemptContent
        contentHandler = nil
        lock.unlock()
        handler?(content ?? UNNotificationContent())
    }

    /// The signed absolute url the server attached, if this push carries one.
    ///
    /// Push `data` values are all strings by contract (shipped builds decode
    /// the inbox's `data` as `[String: String]`, so one non-string breaks the
    /// whole decode) — hence the `String` cast rather than anything cleverer.
    private static func imageURL(in userInfo: [AnyHashable: Any]) -> URL? {
        guard
            let data = userInfo["data"] as? [String: Any],
            let raw = data["image_url"] as? String,
            let url = URL(string: raw),
            url.scheme == "https"
        else { return nil }
        return url
    }

    /// Writes the bytes somewhere `UNNotificationAttachment` can adopt them.
    ///
    /// The initialiser MOVES the file out of our container, so it has to be a
    /// path we own and a name that doesn't collide across concurrent pushes.
    /// The type is declared explicitly instead of being inferred from the file
    /// extension: the signed url ends in `?e=…&s=…`, and a query string is
    /// enough to make extension-sniffing produce an attachment iOS then
    /// refuses to render.
    private static func attachment(for data: Data, from url: URL) -> UNNotificationAttachment? {
        let type = contentType(for: url)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent(
            "thumbnail.\(type.preferredFilenameExtension ?? "jpg")"
        )
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            try data.write(to: file)
            return try UNNotificationAttachment(
                identifier: "post-media",
                url: file,
                options: [UNNotificationAttachmentOptionsTypeHintKey: type.identifier]
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            return nil
        }
    }

    private static func contentType(for url: URL) -> UTType {
        // `pathExtension` on a signed url is still clean — the query lives in
        // `query`, not the path — so this stays a reliable hint. JPEG is the
        // fallback because that is what the uploader writes.
        switch url.pathExtension.lowercased() {
        case "png": return .png
        case "heic": return .heic
        case "gif": return .gif
        default: return .jpeg
        }
    }
}
