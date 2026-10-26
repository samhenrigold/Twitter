import Foundation
import Models

extension TwitterWebSession {
    enum MediaCategory: String, Sendable {
        case image = "tweet_image"
        case gif = "tweet_gif"
        case video = "tweet_video"
    }

    /// Chunked upload to upload.x.com (INIT → APPEND… → FINALIZE → STATUS), the flow x.com uses.

    func uploadMedia(
        _ data: Data, mimeType: String, category: MediaCategory,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        let base = "https://upload.x.com/i/media/upload.json"
        func url(_ items: [String: String]) -> URL {
            var components = URLComponents(string: base)!
            components.queryItems = items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            return components.url!
        }

        let initJSON = try await uploadRequest(
            url([
                "command": "INIT", "total_bytes": "\(data.count)",
                "media_type": mimeType, "media_category": category.rawValue
            ]))
        guard let mediaID = (initJSON["media_id_string"] as? String) ?? (initJSON["media_id"] as? Int).map(String.init)
        else {
            throw TwitterError.api("Twitter didn't accept the upload.")
        }

        let chunkSize = 4 << 20
        var offset = 0
        var segment = 0
        while offset < data.count {
            let chunk = data[offset..<min(offset + chunkSize, data.count)]
            let boundary = "----Twitter\(UUID().uuidString)"
            var body = Data()
            body.append(
                "--\(boundary)\r\nContent-Disposition: form-data; name=\"media\"; filename=\"blob\"\r\nContent-Type: application/octet-stream\r\n\r\n"
                    .data(using: .utf8)!)
            body.append(chunk)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            _ = try await uploadRequest(
                url(["command": "APPEND", "media_id": mediaID, "segment_index": "\(segment)"]),
                body: body, contentType: "multipart/form-data; boundary=\(boundary)")
            offset += chunk.count
            segment += 1
            progress?(Double(offset) / Double(data.count) * (category == .image ? 1 : 0.8))
        }

        var info =
            try await uploadRequest(url(["command": "FINALIZE", "media_id": mediaID]))["processing_info"]
            as? [String: Any]
        // Video and GIF are transcoded server-side; wait until Twitter reports success.
        while let state = info?["state"] as? String, state == "pending" || state == "in_progress" {
            if let percent = info?["progress_percent"] as? Int { progress?(0.8 + Double(percent) / 500) }
            let wait = min(max(info?["check_after_secs"] as? Int ?? 1, 1), 10)
            try await Task.sleep(for: .seconds(wait))
            info =
                try await uploadRequest(url(["command": "STATUS", "media_id": mediaID]), method: "GET")[
                    "processing_info"] as? [String: Any]
        }
        if let state = info?["state"] as? String, state == "failed" {
            let message = (info?["error"] as? [String: Any])?["message"] as? String
            throw TwitterError.api(message ?? "Twitter couldn't process this media.")
        }
        progress?(1)
        return mediaID
    }

    private func uploadRequest(_ url: URL, method: String = "POST", body: Data? = nil, contentType: String? = nil)
        async throws -> [String: Any]
    {
        var request = apiRequest(url: url, method: method, body: body, transactionPath: url.path(), generator: nil)
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if body == nil { request.setValue(nil, forHTTPHeaderField: "Content-Type") }
        request.timeoutInterval = 120
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TwitterError.http(0, "No response") }
        absorbCookies(from: http)
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw TwitterError.unauthorized }
            let json = try? JSONSerialization.jsonObject(with: data)
            throw TwitterError.http(
                http.statusCode, Self.errorMessages(json).first ?? String(decoding: data.prefix(200), as: UTF8.self))
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
