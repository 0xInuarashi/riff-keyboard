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
                        Text(option.localizedTitle)
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
                        Text("Paste a few short messages that sound like you. Riff uses their style when Personalization is selected.")
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
}
