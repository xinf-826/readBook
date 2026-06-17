//
//  LANImportView.swift
//  readBook
//
//  局域网 HTTP 导入：展示二维码与网址，接收同 WiFi 设备上传的 txt。
//

import CoreImage.CIFilterBuiltins
import SwiftUI

struct LANImportView: View {
    @Environment(BookStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var server = LocalImportServer()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    statusSection
                    if let url = server.serverURL {
                        qrSection(url: url)
                        urlSection(url: url)
                    } else if server.isRunning {
                        ProgressView("正在启动服务…")
                            .padding(.top, 40)
                    } else {
                        ContentUnavailableView {
                            Label("服务启动失败", systemImage: "wifi.slash")
                        } description: {
                            Text("请确认已连接 WiFi，且端口 8080 未被占用。")
                        }
                    }
                    recordsSection
                }
                .padding()
            }
            .navigationTitle("局域网导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        server.stop()
                        dismiss()
                    }
                }
                if server.isRunning {
                    ToolbarItem(placement: .primaryAction) {
                        Button("停止服务") { server.stop() }
                    }
                }
            }
            .onAppear { startServerIfNeeded() }
            .onDisappear { server.stop() }
        }
    }

    private var statusSection: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(server.isRunning ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            Text(server.isRunning ? "服务运行中" : "服务已停止")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func qrSection(url: URL) -> some View {
        VStack(spacing: 12) {
            Text("扫码打开上传页")
                .font(.headline)
            if let image = QRCodeImage.generate(from: url.absoluteString) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            }
        }
    }

    @ViewBuilder
    private func urlSection(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("或手动输入地址")
                .font(.headline)
            HStack {
                Text(url.absoluteString)
                    .font(.footnote.monospaced())
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    UIPasteboard.general.string = url.absoluteString
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("复制地址")
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("导入记录")
                .font(.headline)
            if server.uploadRecords.isEmpty {
                Text("暂无上传记录")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(server.uploadRecords.prefix(10)) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.fileName)
                                .lineLimit(1)
                            Text(record.date.formatted(date: .omitted, time: .standard))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(record.status)
                            .font(.caption)
                            .foregroundStyle(record.status.contains("成功") ? .green : .red)
                    }
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func startServerIfNeeded() {
        guard !server.isRunning else { return }
        server.start { data, fileName in
            store.importBook(data: data, fileName: fileName)
        }
    }
}

// MARK: - QR Code

private enum QRCodeImage {
    static func generate(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
