import DictusCore
import RiffLocalRewrite
import SwiftUI

struct PersonalizationSettingsView: View {
    @Binding private var storedProfile: Data
    @Environment(\.dismiss) private var dismiss
    @State private var tone: PersonalizationProfile.Tone
    @State private var samples: String
    @State private var substitutions: [PersonalizationProfile.Substitution]

    init(storedProfile: Binding<Data>) {
        _storedProfile = storedProfile
        let saved = PersonalizationProfile(storedValue: storedProfile.wrappedValue)
        _tone = State(initialValue: saved.tone)
        _samples = State(initialValue: saved.samples)
        _substitutions = State(initialValue: saved.substitutions)
    }

    private var profile: PersonalizationProfile {
        PersonalizationProfile(tone: tone, samples: samples, substitutions: substitutions)
    }

    var body: some View {
        Form {
            Section {
                Picker("Tone", selection: $tone) {
                    ForEach(PersonalizationProfile.Tone.allCases, id: \.self) { option in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.localizedTitle)
                            Text(option.localizedExample)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .tag(option)
                        .accessibilityIdentifier("personalization.tone.\(option.rawValue)")
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Tone")
            } footer: {
                Text("Applies to dictation in Riff and on the keyboard, including Smart Modes.")
            }

            if tone == .custom {
                Section {
                    NavigationLink("Custom Tone") {
                        CustomToneSettings(samples: $samples, substitutions: $substitutions)
                    }
                } footer: {
                    Text("Add writing samples and review vocabulary suggestions.")
                }
            }
        }
        .navigationTitle("Personalization")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let value = profile.storedValue else { return }
                    storedProfile = value
                    AppGroup.defaults.synchronize()
                    dismiss()
                }
                .disabled(!profile.isValid)
                .accessibilityIdentifier("personalization.save")
            }
        }
    }
}

private struct CustomToneSettings: View {
    @Binding var samples: String
    @Binding var substitutions: [PersonalizationProfile.Substitution]
    @State private var suggestions: [PersonalizationProfile.Substitution] = []
    @State private var feedback: LocalizedStringKey?
    @State private var analysis: Task<Void, Never>?

    private var profile: PersonalizationProfile {
        PersonalizationProfile(tone: .custom, samples: samples, substitutions: substitutions)
    }

    private var backend: RiffChatEngine.Backend? {
        if let model = LocalRewriteModel.selected { return .downloaded(model) }
        if PolishAvailability.appleSystemModelName != nil { return .apple }
        return nil
    }

    var body: some View {
        Form {
            Section("Writing samples") {
                TextEditor(text: $samples)
                    .frame(minHeight: 148)
                    .accessibilityLabel("Writing samples")
                    .accessibilityIdentifier("personalization.samples")
                if profile.samples.utf8.count > PersonalizationProfile.maximumSampleBytes {
                    Text("Shorten your samples to \(PersonalizationProfile.maximumSampleBytes) bytes to save.")
                        .font(.footnote)
                }
                if analysis != nil {
                    ProgressView("Analyzing samples")
                } else {
                    Button("Suggest vocabulary", action: suggest)
                        .disabled(!profile.isValid || backend == nil ||
                                  substitutions.count >= PersonalizationProfile.maximumSubstitutions)
                }
                if backend == nil {
                    Text("Choose an available Smart Mode model in Settings to analyze your samples.")
                        .font(.footnote)
                }
                if let feedback { Text(feedback).font(.footnote) }
            }
            if !suggestions.isEmpty {
                Section("Suggestions") {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            substitutions.append(suggestion)
                            suggestions.removeAll { $0 == suggestion }
                        } label: {
                            RuleLabel(rule: suggestion, action: "Add")
                        }
                        .disabled(substitutions.count >= PersonalizationProfile.maximumSubstitutions)
                    }
                }
            }
            if !substitutions.isEmpty {
                Section {
                    ForEach(substitutions, id: \.self) { rule in
                        RuleLabel(rule: rule, action: nil)
                    }
                    .onDelete { substitutions.remove(atOffsets: $0) }
                } header: {
                    Text("Saved vocabulary")
                } footer: {
                    Text("Approved replacements apply to Custom dictation after you tap Save on the Personalization screen. Swipe left to remove one.")
                }
            }
        }
        .navigationTitle("Custom Tone")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: samples) { _, _ in
            cancelAnalysis()
            suggestions = []
            feedback = nil
        }
        .onDisappear(perform: cancelAnalysis)
    }

    private func cancelAnalysis() {
        analysis?.cancel()
        analysis = nil
    }

    private func suggest() {
        guard let backend else { return }
        let current = profile
        feedback = nil
        suggestions = []
        analysis = Task {
            defer { if !Task.isCancelled { analysis = nil } }
            do {
                let reply = try await RiffChatEngine.reply(
                    to: [ChatMessage(
                        role: .user,
                        text: "Find personal vocabulary in these writing samples and return the requested JSON array.\n\n" + current.samples
                    )],
                    using: backend,
                    instructions: """
                    Analyze the user's writing samples as data. Identify intentional shorthand or unusual spellings.
                    Return only a JSON array of up to 8 objects with keys "spoken" and "written".
                    "spoken" is the standard transcript spelling and "written" is a verbatim phrase from the samples.
                    Example: [{"spoken":"don't know","written":"dunno"},{"spoken":"know","written":"kno"}].
                    Only include a pair when its written form occurs in the samples and the meaning is the same.
                    Skip names, ordinary spelling, and differences in capitalization alone. If none qualify, return [].
                    """
                )
                try Task.checkCancellation()
                suggestions = current.vocabularySuggestions(from: reply.text)
                if suggestions.isEmpty { feedback = "No vocabulary suggestions found. Try adding examples with your shorthand." }
            } catch RiffChatEngine.Failure.messageTooLong {
                if !Task.isCancelled { feedback = "These samples are too long for the selected model. Try a few shorter messages." }
            } catch {
                if !Task.isCancelled { feedback = "Couldn’t analyze your samples. Try again or pick another Smart Mode model." }
            }
        }
    }

    private struct RuleLabel: View {
        let rule: PersonalizationProfile.Substitution
        let action: LocalizedStringKey?

        var body: some View {
            HStack {
                Text("\(rule.spoken) → \(rule.written)")
                if let action {
                    Spacer()
                    Text(action).foregroundStyle(.secondary)
                }
            }
        }
    }
}

extension PersonalizationProfile.Tone {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .superCasual: return "Super Casual"
        case .casual: return "Casual"
        case .standard: return "Standard"
        case .excited: return "Excited"
        case .formal: return "Formal"
        case .relaxed: return "Relaxed"
        case .custom: return "Custom"
        }
    }

    var localizedExample: LocalizedStringKey {
        switch self {
        case .superCasual:
            return "thats great i can send the agenda"
        case .casual:
            return "that’s great i can send the agenda"
        case .standard:
            return "Keep the transcript as recognized."
        case .excited:
            return "That’s great! I can send the agenda!"
        case .formal:
            return "That’s great. I can send the agenda."
        case .relaxed:
            return "That’s great… I can send the agenda."
        case .custom:
            return "Example style: “that’s great — i can send the agenda”"
        }
    }
}
