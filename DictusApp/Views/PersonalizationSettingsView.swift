import DictusCore
import SwiftUI

struct PersonalizationSettingsView: View {
    @Binding private var storedProfile: Data
    @Environment(\.dismiss) private var dismiss
    @State private var tone: PersonalizationProfile.Tone
    @State private var samples: String

    init(storedProfile: Binding<Data>) {
        _storedProfile = storedProfile
        let saved = PersonalizationProfile(storedValue: storedProfile.wrappedValue)
        _tone = State(initialValue: saved.tone)
        _samples = State(initialValue: saved.samples)
    }

    private var profile: PersonalizationProfile {
        PersonalizationProfile(tone: tone, samples: samples)
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
            }

            if tone == .custom || !profile.isValid {
                Section {
                    TextEditor(text: $samples)
                        .frame(minHeight: 148)
                        .accessibilityLabel("Writing samples")
                        .accessibilityIdentifier("personalization.samples")
                } header: {
                    Text("Writing samples")
                } footer: {
                    if profile.samples.utf8.count > PersonalizationProfile.maximumSampleBytes {
                        Text("Shorten your samples to \(PersonalizationProfile.maximumSampleBytes) bytes to save.")
                    } else {
                        Text("Paste a few short messages that sound like you. Riff uses their capitalization and punctuation.")
                    }
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

extension PersonalizationProfile.Tone {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .superCasual: return "Super Casual"
        case .casual: return "Casual"
        case .excited: return "Excited"
        case .formal: return "Formal"
        case .relaxed: return "Relaxed"
        case .custom: return "Custom"
        }
    }

    var localizedExample: LocalizedStringKey {
        switch self {
        case .superCasual:
            return "that’s great! i can send the agenda"
        case .casual:
            return "That’s great, I can send the agenda."
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
