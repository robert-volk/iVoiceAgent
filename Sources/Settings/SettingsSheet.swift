import SwiftUI

/// The single settings surface in this app — not a screen, a sheet, reachable
/// only from the first-launch note or a long-press on the header (see
/// AgentView). Holds the Anthropic key (required — every answer is a Claude
/// API call), the optional Breeze key + voice ID that upgrades the spoken
/// voice, and a plain view of what's been learned so far, with the ability
/// to forget any of it.
struct SettingsSheet: View {
    @ObservedObject var memory: MemoryStore

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared

    @State private var anthropicKey: String = Keychain.load(.anthropicAPIKey) ?? ""
    @State private var breezeKey: String = Keychain.load(.breezeAPIKey) ?? ""
    @State private var breezeVoiceID: String = AppSettings.shared.breezeVoiceID
    @State private var isValidatingBreeze = false
    @State private var breezeValidationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-...", text: $anthropicKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Anthropic API key")
                } footer: {
                    Text("Required — every answer is a Claude API call. Stored in Keychain, never in source. Question text and what's remembered about you are sent to Anthropic; see the README for the full picture of what leaves this device.")
                }

                Section {
                    SecureField("brz_... (Breeze API key)", text: $breezeKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { validateBreezeKeyIfNeeded() }
                    TextField("voc_... (Breeze voice ID)", text: $breezeVoiceID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if isValidatingBreeze {
                        ProgressView()
                    } else if let message = breezeValidationMessage {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Voice (optional)")
                } footer: {
                    Text("Without both a key and a voice ID, Voice Agent speaks with the on-device voice — clearly synthetic, but free and works offline. A Breeze key and voice ID together sound far more natural. This is not the Claude voice-chat voice: Anthropic doesn't expose that voice, or any text-to-speech at all, through its API. Find your key and voice ID at breezeblue.ai — the key starts with \"brz_\", voice IDs with \"voc_\".")
                }

                Section {
                    if memory.facts.isEmpty {
                        Text("Nothing remembered yet — it learns as you talk.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(memory.facts) { fact in
                            Text(fact.text)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                memory.forget(memory.facts[index].id)
                            }
                        }
                        Button("Forget everything", role: .destructive) {
                            memory.forgetEverything()
                        }
                    }
                } header: {
                    Text("What I remember")
                } footer: {
                    Text("Learned automatically from conversation and stored only on this device. Swipe to forget something specific.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save()
                        dismiss()
                    }
                }
            }
            // `.onDisappear` fires no matter how the sheet closes -- the
            // Done button, a swipe-down, or tapping outside. Saving only
            // from the Done button's action meant a swipe-to-dismiss (the
            // default, natural gesture for a sheet) silently discarded
            // everything typed, including a just-entered voice ID or key.
            .onDisappear { save() }
        }
    }

    private func validateBreezeKeyIfNeeded() {
        let trimmed = breezeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            breezeValidationMessage = nil
            return
        }
        isValidatingBreeze = true
        Task {
            let isValid = await BreezeVoice.validate(apiKey: trimmed)
            isValidatingBreeze = false
            breezeValidationMessage = isValid ? "Key looks good." : "Couldn't verify this key."
        }
    }

    private func save() {
        let trimmedAnthropic = anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAnthropic.isEmpty {
            Keychain.delete(.anthropicAPIKey)
        } else {
            Keychain.save(trimmedAnthropic, for: .anthropicAPIKey)
        }

        let trimmedBreeze = breezeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBreeze.isEmpty {
            Keychain.delete(.breezeAPIKey)
        } else {
            Keychain.save(trimmedBreeze, for: .breezeAPIKey)
        }

        let trimmedVoiceID = breezeVoiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.breezeVoiceID = trimmedVoiceID.isEmpty ? AppSettings.defaultBreezeVoiceID : trimmedVoiceID
    }
}
