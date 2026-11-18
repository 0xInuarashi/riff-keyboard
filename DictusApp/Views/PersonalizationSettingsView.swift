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

    var localizedExample: LocalizedStringKey {
        switch self {
        case .superCasual:
            return "hey! can we move the meeting to monday? i can send the agenda."
        case .casual:
            return "Hey, can we move the meeting to Monday? I can send the agenda."
        case .excited:
            return "Hey! Could we move the meeting to Monday? I’d be happy to send the agenda!"
        case .formal:
            return "Would it be possible to reschedule the meeting for Monday? I can send the agenda."
        case .relaxed:
            return "How about moving the meeting to Monday? I can send the agenda if that helps."
        case .custom:
            return "Example style: “quick one — monday for the meeting? i can send the agenda.”"
        }
    }
}
