import CryptoKit
import DictusCore
import SwiftUI

struct LocalRewriteSettings: View {
    @AppStorage(LocalRewriteModel.preferenceKey, store: AppGroup.defaults)
    private var selection = LocalRewriteModel.apple

    @StateObject private var downloads = LocalRewriteDownloads.shared

    var body: some View {
        List {
            Section {
                Button {
                    selection = LocalRewriteModel.apple
                } label: {
                    modelLabel("Apple Intelligence", selected: selection == LocalRewriteModel.apple)
                }
                .disabled(downloads.activeID != nil)
            } footer: {
                Text("Apple Intelligence uses the system model on supported devices.")
            }

            Section {
                ForEach(LocalRewriteModel.catalog) { model in
                    Button {
                        downloads.select(model)
                    } label: {
                        modelRow(model)
                    }
                    .disabled(downloads.activeID != nil)
                    .accessibilityIdentifier("rewriteModel.\(model.id)")
                }
                if downloads.activeID != nil {
                    Button("Cancel download", role: .cancel) { downloads.cancel() }
                }
                if let error = downloads.error {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Downloadable local models")
            } footer: {
                Text("Downloads are one-time. Smart Modes run on this iPhone with the selected model.")
            }
        }
        .navigationTitle("Smart Mode model")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func modelLabel(_ label: LocalizedStringKey, selected: Bool) -> some View {
        HStack {
            Text(label).foregroundStyle(.primary)
            Spacer()
            if selected { Image(systemName: "checkmark").accessibilityLabel("Selected") }
        }
    }

    private func modelRow(_ model: LocalRewriteModel) -> some View {
        let installed = model.isInstalled
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name).foregroundStyle(.primary)
                Text(ByteCountFormatter.string(fromByteCount: Int64(model.bytes), countStyle: .file))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if downloads.activeID == model.id {
                ProgressView().accessibilityLabel("Downloading model")
            } else if selection == model.id && installed {
                Image(systemName: "checkmark").accessibilityLabel("Selected")
            } else if !installed {
                Image(systemName: "arrow.down.circle").accessibilityLabel("Download model")
            }
        }
    }
}

@MainActor
private final class LocalRewriteDownloads: ObservableObject {
    static let shared = LocalRewriteDownloads()

    @Published private(set) var activeID: String?
    @Published private(set) var error: LocalizedStringKey?
    private var task: Task<Void, Never>?

    func select(_ model: LocalRewriteModel) {
        guard task == nil else { return }
        error = nil
        if model.isInstalled {
            AppGroup.defaults.set(model.id, forKey: LocalRewriteModel.preferenceKey)
            return
        }
        activeID = model.id
        task = Task {
            defer {
                activeID = nil
                task = nil
            }
            do {
                try await Self.install(model)
                try Task.checkCancellation()
                AppGroup.defaults.set(model.id, forKey: LocalRewriteModel.preferenceKey)
            } catch {
                if !Task.isCancelled {
                    self.error = "The model could not be downloaded. Tap it to retry."
                }
            }
        }
    }

    func cancel() { task?.cancel() }

    private nonisolated static func install(_ model: LocalRewriteModel) async throws {
        guard let destination = model.fileURL else { throw CocoaError(.fileNoSuchFile) }
        let (temporary, response) = try await URLSession.shared.download(from: model.url)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize == model.bytes else {
            throw URLError(.badServerResponse)
        }
        let file = try FileHandle(forReadingFrom: temporary)
        defer { try? file.close() }
        var digest = SHA256()
        while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            digest.update(data: chunk)
        }
        let checksum = digest.finalize().map { String(format: "%02x", $0) }.joined()
        guard checksum == model.sha256 else { throw URLError(.cannotDecodeContentData) }
        let files = FileManager.default
        let directory = destination.deletingLastPathComponent()
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        var cacheDirectory = directory
        var metadata = URLResourceValues()
        metadata.isExcludedFromBackup = true
        try cacheDirectory.setResourceValues(metadata)
        if files.fileExists(atPath: destination.path) {
            _ = try files.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try files.moveItem(at: temporary, to: destination)
        }
    }
}
