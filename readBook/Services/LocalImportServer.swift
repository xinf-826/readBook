//
//  LocalImportServer.swift
//  readBook
//
//  局域网 HTTP 导入服务：8080 端口提供上传页面，接收 txt 并回调导入。
//

import Foundation
import Network
import Observation
import UIKit

struct LANUploadRecord: Identifiable {
    let id = UUID()
    let fileName: String
    let date: Date
    var status: String
}

@Observable
final class LocalImportServer {
    static let port: UInt16 = 8080

    private(set) var isRunning = false
    private(set) var serverURL: URL?
    private(set) var uploadRecords: [LANUploadRecord] = []

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.readbook.lan-import")
    private var onUpload: ((Data, String) -> String)?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    func start(onUpload: @escaping (Data, String) -> String) {
        guard !isRunning else { return }
        self.onUpload = onUpload
        beginBackgroundTask()

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!)
        } catch {
            stopBackgroundTask()
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    self.isRunning = true
                    if let ip = Self.localWiFiAddress() {
                        self.serverURL = URL(string: "http://\(ip):\(Self.port)")
                    }
                }
            case .failed, .cancelled:
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.serverURL = nil
                }
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        onUpload = nil
        DispatchQueue.main.async {
            self.isRunning = false
            self.serverURL = nil
        }
        stopBackgroundTask()
    }

    // MARK: - Connection

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, accumulated: Data())
    }

    private func receive(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                connection.cancel()
                print("[LANImport] receive error: \(error)")
                return
            }
            var buffer = accumulated
            if let data { buffer.append(data) }

            if let response = self.processRequest(buffer) {
                self.send(response, on: connection)
                return
            }
            if isComplete {
                connection.cancel()
                return
            }
            self.receive(on: connection, accumulated: buffer)
        }
    }

    private func send(_ response: Data, on connection: NWConnection) {
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - HTTP

    private func processRequest(_ data: Data) -> Data? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let headerText = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let idx = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<idx]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let bodyStart = headerEnd.upperBound

        if method == "POST", let lengthStr = headers["content-length"], let length = Int(lengthStr) {
            let headerByteCount = data.distance(from: data.startIndex, to: bodyStart)
            guard data.count >= headerByteCount + length else { return nil }
            let body = data[bodyStart..<data.index(data.startIndex, offsetBy: headerByteCount + length)]
            switch path {
            case "/upload":
                return handleUpload(body: Data(body), headers: headers)
            default:
                return Self.httpResponse(status: 404, contentType: "text/plain", body: Data("Not Found".utf8))
            }
        }

        switch (method, path) {
        case ("GET", "/"), ("GET", "/index.html"):
            return Self.httpResponse(status: 200, contentType: "text/html; charset=utf-8", body: Self.uploadHTML(records: uploadRecords))
        default:
            return Self.httpResponse(status: 404, contentType: "text/plain", body: Data("Not Found".utf8))
        }
    }

    private func handleUpload(body: Data, headers: [String: String]) -> Data {
        let contentType = headers["content-type"] ?? ""
        guard let parsed = Self.parseMultipart(body: body, contentType: contentType) else {
            return Self.httpResponse(status: 400, contentType: "text/plain", body: Data("Invalid upload".utf8))
        }
        let status: String
        if let handler = onUpload {
            status = handler(parsed.data, parsed.fileName)
        } else {
            status = "失败：服务未就绪"
        }
        let record = LANUploadRecord(fileName: parsed.fileName, date: Date(), status: status)
        DispatchQueue.main.async { self.uploadRecords.insert(record, at: 0) }
        var records = uploadRecords
        records.insert(record, at: 0)
        return Self.httpResponse(status: 200, contentType: "text/html; charset=utf-8", body: Self.uploadHTML(records: records))
    }

    private static func httpResponse(status: Int, contentType: String, body: Data) -> Data {
        let statusText = status == 200 ? "OK" : "Error"
        let header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        return response
    }

    // MARK: - Multipart

    private static func parseMultipart(body: Data, contentType: String) -> (fileName: String, data: Data)? {
        guard let boundaryRange = contentType.range(of: "boundary=") else { return nil }
        let boundary = "--" + String(contentType[boundaryRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bodyString = String(data: body, encoding: .utf8) ?? String(data: body, encoding: .isoLatin1) else { return nil }

        // 二进制安全：在 Data 层面查找 boundary
        guard let boundaryData = boundary.data(using: .utf8) else { return nil }
        var searchRange = body.startIndex..<body.endIndex
        var parts: [(headers: String, data: Data)] = []

        while let range = body.range(of: boundaryData, options: [], in: searchRange) {
            let afterBoundary = range.upperBound
            if afterBoundary >= body.endIndex { break }
            let nextStart = body.index(afterBoundary, offsetBy: 0, limitedBy: body.endIndex) ?? body.endIndex
            if nextStart >= body.endIndex { break }
            if body[nextStart..<min(body.index(nextStart, offsetBy: 2, limitedBy: body.endIndex) ?? body.endIndex, body.endIndex)] == Data("--".utf8) {
                break
            }
            guard let partEnd = body.range(of: boundaryData, options: [], in: afterBoundary..<body.endIndex) else { break }
            let partData = body[afterBoundary..<partEnd.lowerBound]
            if let headerSep = partData.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = partData[..<headerSep.lowerBound]
                let fileData = partData[headerSep.upperBound...]
                let headerStr = String(data: headerData, encoding: .utf8) ?? ""
                parts.append((headerStr, Data(fileData)))
            }
            searchRange = partEnd.upperBound..<body.endIndex
        }

        for part in parts {
            guard part.headers.contains("filename=") else { continue }
            let name = extractFileName(from: part.headers) ?? "upload.txt"
            let trimmed = trimTrailingCRLF(from: part.data)
            guard !trimmed.isEmpty else { continue }
            return (name, trimmed)
        }
        return nil
    }

    private static func extractFileName(from headers: String) -> String? {
        guard let range = headers.range(of: "filename=\"") else { return nil }
        let rest = headers[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    private static func trimTrailingCRLF(from data: Data) -> Data {
        var result = data
        while result.count >= 2, result.suffix(2) == Data("\r\n".utf8) {
            result.removeLast(2)
        }
        return result
    }

    // MARK: - HTML

    private static func uploadHTML(records: [LANUploadRecord]) -> Data {
        let rows = records.prefix(20).map { record in
            let status = record.status.contains("成功") ? "ok" : "fail"
            return "<tr class=\"\(status)\"><td>\(escapeHTML(record.fileName))</td><td>\(escapeHTML(record.status))</td><td>\(formatDate(record.date))</td></tr>"
        }.joined()
        let html = """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8"/>
          <meta name="viewport" content="width=device-width, initial-scale=1"/>
          <title>readBook 上传</title>
          <style>
            body { font-family: -apple-system, sans-serif; max-width: 560px; margin: 40px auto; padding: 0 16px; }
            h1 { font-size: 1.4rem; }
            form { margin: 24px 0; padding: 20px; border: 1px dashed #ccc; border-radius: 12px; }
            input[type=file] { width: 100%; margin-bottom: 12px; }
            button { background: #007aff; color: #fff; border: none; padding: 10px 20px; border-radius: 8px; font-size: 1rem; }
            table { width: 100%; border-collapse: collapse; margin-top: 24px; font-size: 0.9rem; }
            th, td { border-bottom: 1px solid #eee; padding: 8px; text-align: left; }
            tr.ok td:nth-child(2) { color: #34c759; }
            tr.fail td:nth-child(2) { color: #ff3b30; }
          </style>
        </head>
        <body>
          <h1>📚 readBook 局域网导入</h1>
          <p>选择 .txt 文件上传到 iPhone 书架。</p>
          <form action="/upload" method="post" enctype="multipart/form-data">
            <input type="file" name="file" accept=".txt,text/plain" required />
            <button type="submit">上传并导入</button>
          </form>
          <h2>导入记录</h2>
          <table>
            <thead><tr><th>文件名</th><th>状态</th><th>时间</th></tr></thead>
            <tbody>\(rows.isEmpty ? "<tr><td colspan=\"3\">暂无记录</td></tr>" : rows)</tbody>
          </table>
        </body>
        </html>
        """
        return Data(html.utf8)
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    // MARK: - Network helpers

    private static func localWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            address = String(cString: hostname)
            break
        }
        return address
    }

    // MARK: - Background task

    private func beginBackgroundTask() {
        stopBackgroundTask()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "LANImport") { [weak self] in
            self?.stop()
        }
    }

    private func stopBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
