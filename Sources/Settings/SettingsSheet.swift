import SwiftUI

/// The single settings surface in this app — not a screen, a sheet, reachable
/// only from the first-launch note or a long-press on the header (see
/// AgentView). Holds exactly three things: the Anthropic key (required —
/// every answer is a Claude API call), the one-time Drive folder pick, and
/// the optional ElevenLabs key + voice ID that upgrades the spoken voice.
struct SettingsSheet: View {
    /// Called with the picked folder URL. The `.fileImporter` that produces
    /// it lives on *this* view, not the presenter — a `.fileImporter`
    /// attached to the view behind an already-presented `.sheet` can't
    /// present its own modal (a sheet can't present a sheet from underneath
    /// itself), so the folder picker has to be owned here.
    let onPickFolder: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared

    @State private var anthropicKey: String = Keychain.load(.anthropicAPIKey) ?? ""
    @State private var elevenLabsKey: String = Keychain.load(.elevenLabsAPIKey) ?? ""
    @State private var elevenLabsVoiceID: String = AppSettings.shared.elevenLabsVoiceID
    @State private var isValidatingElevenLabs = false
    @State private var elevenLabsValidationMessage: String?
    @State private var showingFolderPicker = false

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
                    Text("Required — every answer is a Claude API call. Stored in Keychain, never in source. Question text and retrieved excerpts are sent to Anthropic; see the README for the full picture of what leaves this device.")
                }

                Section {
                    Button(action: { showingFolderPicker = true }) {
                        Label(folderStatusText, systemImage: "folder")
                    }
                } header: {
                    Text("Documents folder")
                } footer: {
                    Text("Pick the \"Voice Agent\" folder inside Google Drive in the Files app. Drop documents into that same folder on your PC via Google Drive for desktop, and they'll show up here on your next rescan.")
                }

                Section {
                    SecureField("ElevenLabs key (optional)", text: $elevenLabsKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { validateElevenLabsKeyIfNeeded() }
                    TextField("Voice ID", text: $elevenLabsVoiceID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if isValidatingElevenLabs {
                        ProgressView()
                    } else if let message = elevenLabsValidationMessage {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Voice (optional)")
                } footer: {
                    Text("Without a key, Voice Agent speaks with the on-device voice — clearly synthetic, but free and works offline. An ElevenLabs key sounds far more natural. This is not the Claude voice-chat voice: Anthropic doesn't expose that voice, or any text-to-speech at all, through its API.")
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
            .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    onPickFolder(url)
                }
            }
        }
    }

    private var folderStatusText: String {
        settings.corpusBookmarkData != nil
            ? "Voice Agent folder selected — tap to change"
            : "Pick your Voice Agent folder"
    }

    private func validateElevenLabsKeyIfNeeded() {
        let trimmed = elevenLabsKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            elevenLabsValidationMessage = nil
            return
        }
        isValidatingElevenLabs = true
        Task {
            let isValid = await ElevenLabsVoice.validate(apiKey: trimmed)
            isValidatingElevenLabs = false
            elevenLabsValidationMessage = isValid ? "Key looks good." : "Couldn't verify this key."
        }
    }

    private func save() {
        let trimmedAnthropic = anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAnthropic.isEmpty {
            Keychain.delete(.anthropicAPIKey)
        } else {
            Keychain.save(trimmedAnthropic, for: .anthropicAPIKey)
        }

        let trimmedEleven = elevenLabsKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEleven.isEmpty {
            Keychain.delete(.elevenLabsAPIKey)
        } else {
            Keychain.save(trimmedEleven, for: .elevenLabsAPIKey)
        }

        let trimmedVoiceID = elevenLabsVoiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.elevenLabsVoiceID = trimmedVoiceID.isEmpty ? AppSettings.defaultElevenLabsVoiceID : trimmedVoiceID
    }
}
