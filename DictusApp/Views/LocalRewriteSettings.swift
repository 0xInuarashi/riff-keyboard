import CryptoKit
import DictusCore
import SwiftUI
import UIKit

struct LocalRewriteSettings: View {
    @AppStorage(LocalRewriteModel.preferenceKey, store: AppGroup.defaults)
    private var selection = LocalRewriteModel.apple

    var body: some View {
        OnDeviceModelPicker(
            selection: $selection,
            title: "Smart Mode model",
            caption: "Smart Modes and transcription cleanup run on this iPhone with the selected model."
        )
    }
}

struct OnDeviceModelPicker: View {
    @Binding var selection: String
    let title: LocalizedStringKey
    let caption: LocalizedStringKey
    let allowsUnavailableApple: Bool

    @ObservedObject private var downloads = LocalRewriteDownloads.shared

    init(selection: Binding<String>, title: LocalizedStringKey, caption: LocalizedStringKey,
         allowsUnavailableApple: Bool = true) {
        self._selection = selection
        self.title = title
        self.caption = caption
        self.allowsUnavailableApple = allowsUnavailableApple
    }

    var body: some View {
        let systemModelName = PolishAvailability.appleSystemModelName
        List {
            Section {
                Button {
                    selection = LocalRewriteModel.apple
                } label: {
                    modelLabel(systemModelName ?? "Apple Intelligence", selected: selection == LocalRewriteModel.apple)
                }
                .disabled(downloads.activeID != nil || (!allowsUnavailableApple && systemModelName == nil))
                .accessibilityIdentifier("rewriteModel.apple")
            } footer: {
                if systemModelName != nil {
                    Text("iOS chooses the Apple model for this device.")
                } else {
                    Text("Apple Intelligence is currently unavailable on this iPhone.")
                }
            }

            Section {
                ForEach(LocalRewriteModel.catalog) { model in
                    Button {
                        downloads.select(model) {
                            selection = model.id
                            AppGroup.defaults.synchronize()
                        }
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
                Text(caption)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func modelLabel(_ label: String, selected: Bool) -> some View {
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

struct PolishTranscriptionRows: View {
    let usesLocalModel: Bool

    @AppStorage(SharedKeys.polishEnabled, store: AppGroup.defaults)
    private var polishEnabled = false

    var body: some View {
        if usesLocalModel || PolishAvailability.isToggleVisible {
            Toggle(isOn: $polishEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Polish transcription")
                    Text("Uses your Smart Mode model to clean up punctuation, filler words, and false starts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("settings.polishTranscription")
            if !usesLocalModel { polishStateFooter }
        }
    }

    /// Footer row under the polish toggle — surfaces the specific reason
    /// Apple Foundation Models is or isn't usable. When the state is `.available`
    /// no footer is shown (the toggle alone is enough).
    @ViewBuilder
    private var polishStateFooter: some View {
        let state = PolishAvailability.state
        if state != .available {
            VStack(alignment: .leading, spacing: 6) {
                Text(polishStateMessage(for: state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if PolishAvailability.canOpenSystemSettings(for: state) {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Open iPhone Settings")
                            .font(.caption.bold())
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// User-facing explanation per availability state. Strings live in this
    /// view so Localizable.xcstrings can auto-detect them.
    ///
    /// WHY `LocalizedStringKey` (#792): `Text` shows a `String` verbatim, so these
    /// sentences stayed English on a French iPhone. A key is looked up in the catalog,
    /// and the interpolated `reason` below becomes its `%@`.
    private func polishStateMessage(for state: PolishAvailabilityState) -> LocalizedStringKey {
        switch state {
        case .available:
            return ""
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is required for polish. Enable it in iPhone Settings → Apple Intelligence & Siri. Apple requires Siri and your iPhone to use the same language — if Siri is in English and your iPhone is in French (or vice versa), Apple Intelligence stays off."
        case .modelNotReady:
            return "The Apple Intelligence model is downloading on your device. Try again in a few minutes."
        case .deviceNotEligible:
            return "Apple Intelligence isn't supported on this device. Polish requires an iPhone 15 Pro / 15 Pro Max or newer."
        case .osTooOld:
            return "Polish requires iOS 26 or later."
        case .sdkMissing:
            return "Polish isn't available in this build of Riff."
        case .other(let reason):
            return "Apple Intelligence is unavailable (\(reason))."
        }
    }
}

@MainActor
private final class LocalRewriteDownloads: ObservableObject {
    static let shared = LocalRewriteDownloads()

    @Published private(set) var activeID: String?
    @Published private(set) var error: LocalizedStringKey?
    private var task: Task<Void, Never>?

    func select(_ model: LocalRewriteModel, activate: @escaping () -> Void) {
        guard task == nil else { return }
        error = nil
        if model.isInstalled {
            activate()
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
                activate()
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
