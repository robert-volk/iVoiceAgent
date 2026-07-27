# Voice Agent

A single-screen iOS app: tap once, talk, and it answers out loud — grounded **only** in the
documents you keep in one folder. If the answer isn't in your documents, it says so out loud,
then checks the web, and the screen always shows which source it's using.

Design: **Terminal** — monospaced, phosphor-green-on-black, no orb; the transcript itself is the
screen, with a blinking caret standing in for "the agent is thinking/talking."

---

## ⚠️ Two honest notes before you set this up

### This is not the Claude voice-chat voice

Anthropic's API has no text-to-speech endpoint, and the voices used in Claude's own voice mode
aren't published or licensed for third-party apps to use. There was no way to build "the same
voice" — so this app doesn't pretend to. It ships two voices behind one `VoiceProvider` protocol:

- **On-device (default, always available):** `AVSpeechSynthesizer` — free, works offline, clearly
  synthetic. This is what you get with no ElevenLabs key entered.
- **ElevenLabs (opt-in):** paste a key in **Settings** (long-press the header, or tap the
  first-launch note) and the app switches to ElevenLabs' Flash v2.5 model — a warm, conversational
  preset by default, changeable via the Voice ID field in the same sheet. This is the closest
  practical stand-in for a natural voice, not a claim of matching any specific product's voice.

### This app is not fully local

Every answer is a Claude API call (`claude-opus-5`). Speech-to-text stays entirely on-device, and
your documents live in your own Google Drive (or the local sandbox fallback) — but **the question
text and the retrieved excerpts from your documents are sent to Anthropic** on every turn, and
**web search queries leave the device** whenever the agent decides your folder doesn't have the
answer. There's a one-line version of this on first launch; this is the full version.

---

## Setup

You need, in order:

1. **An Anthropic API key** — get one at [console.anthropic.com](https://console.anthropic.com).
   Required; nothing works without it.
2. **A documents folder, bridged through Google Drive** (see below) — optional in the sense that the
   app runs without it (falling back to an empty local folder), but the whole point of the app is
   moot without it.
3. **An ElevenLabs API key** (optional) — get one at [elevenlabs.io](https://elevenlabs.io) if you
   want the more natural voice.

All three are entered in the same place: **Settings**, opened by long-pressing the header or
tapping the note under the controls on first launch.

### The Google Drive folder bridge (Windows ↔ iPhone, no Mac needed)

The developer's PC is Windows, and iOS has no way to read a Windows folder directly. The bridge is
Google Drive, which both ends already understand:

1. **On your PC**, install [Google Drive for desktop](https://www.google.com/drive/download/) if
   you don't have it, sign in, and create a folder named **`Voice Agent`** somewhere inside your
   Drive (e.g. `Google Drive/My Drive/Voice Agent`). Drop your documents in there — PDFs, `.txt`,
   `.md`, `.csv`, `.rtf`, `.docx` are all read.
2. **On your iPhone**, make sure the **Google Drive app** is installed and signed in (this is what
   registers Drive as a location the Files app can browse — you don't need to open the Drive app
   itself day-to-day, just have it installed and signed in once).
3. **In Voice Agent**, open Settings and tap **"Pick your Voice Agent folder."** This opens the
   system Files picker — navigate to **Google Drive → Voice Agent** (the same folder from step 1)
   and select it. The app remembers this folder from then on (a security-scoped bookmark, not a
   copy) — you won't need to pick it again unless you reinstall.
4. From then on, drop a new file into that folder on your PC, and it'll show up in the app's index
   the next time you **foreground the app or tap the header to rescan**. There's no instant live
   sync — Google Drive's iOS integration doesn't reliably push change notifications to a
   third-party app in real time, so a rescan is the trigger rather than something automatic firing
   the moment a file lands.
5. The **`+`** button on the main screen does the reverse: pick a file on your phone, and it gets
   copied into the same Drive folder, syncing back to your PC.

**The honest tradeoff:** this means Voice Agent needs a Google account and your documents pass
through Google's sync infrastructure — unlike the fully local, no-account default in this
developer's other apps. That's the price of a folder that's genuinely live on both a Windows PC
and an iPhone without a Mac in the loop. The app itself still creates no account of its own and
never sees your Google credentials — it only reads a folder the OS's Files app already has access
to, via a standard document picker and a security-scoped bookmark.

If you skip the folder pick entirely, the app uses an empty local folder in its own sandbox
instead (also reachable via the Files app, since file sharing is enabled) — everything still runs,
there's just nothing to be grounded in until you either pick the Drive folder or use **`+`** to add
files locally.

---

## How the grounding actually works

1. **Indexing** (on launch, on foreground, or when you tap the header): every supported file in
   the active folder gets its text extracted, split into ~800-token overlapping chunks (page-aware
   for PDFs, so a chunk never crosses a page boundary), and embedded on-device with `NLEmbedding` —
   no API call, no cost, nothing leaves the phone for this step. Chunks are cached and only
   re-embedded when a file actually changes.
2. **Retrieval**: your question is embedded the same way, and the top 6 chunks by cosine similarity
   (above a tunable floor) are pulled out as candidate excerpts.
3. **The Claude call**: those excerpts are sent as citation-enabled `document` content blocks ahead
   of your question, with adaptive thinking left **on** (disabling it on this model can cause tool
   calls to leak into visible text instead of actually running — see the code comment in
   `ClaudeClient.swift`) and the `web_search` tool available as a fallback.
4. **The source chip**: the screen's colour flips from phosphor green ("local · filename") to amber
   ("web · N results") the instant the model's stream shows it invoking `web_search` — not by
   guessing from the model's wording. Citations attached to the response map straight back to the
   real filename and page you retrieved, via the request's own document index, so the chip is never
   trusting the model to remember a filename correctly.
5. The system prompt (`SystemPrompt.swift`) requires the model to say, out loud, that it's leaving
   your folder *before* it starts searching — "That's not in your documents, so I'm checking the
   web," or similar, varied each time.

---

## Building from Windows (no Mac required)

Same pattern as this developer's other iOS apps: **XcodeGen + GitHub Actions → unsigned IPA →
AltStore sideload.**

### Option A — you have Mac access

Open `project.yml` with Xcode (or run `xcodegen generate` if you have XcodeGen installed, then open
the generated `.xcodeproj`), plug in a device, and run. You'll need to set your own signing team
since the repo ships with signing disabled for the CI path.

### Option B — no Mac (this developer's actual setup)

1. Push this repo to GitHub.
2. `.github/workflows/ios-build.yml` runs on a `macos-15` GitHub-hosted runner: installs XcodeGen
   from its GitHub release (not Homebrew — that fails on the runner), generates
   `VoiceAgent.xcodeproj`, builds an **unsigned** app (`CODE_SIGNING_ALLOWED=NO`), and uploads
   **`VoiceAgent-unsigned.ipa`** as a workflow artifact. No Apple credentials ever touch GitHub.
3. Download the artifact from the Actions run (or trigger one manually via **Run workflow**).
4. Sideload with **[AltServer for Windows](https://altstore.io)**: install AltServer on your PC,
   connect your iPhone over USB, and use it to install the downloaded `.ipa`, signed on-the-fly
   with your own free Apple ID.
5. Apps sideloaded this way **expire after 7 days** and need re-signing — AltStore can do this
   automatically over Wi-Fi if left running, or reconnect via USB weekly. A $99/year Apple Developer
   account removes this limit but isn't required.

---

## Project layout

```
project.yml                      XcodeGen project definition
Resources/Info.plist             Bundle config, mic/speech usage strings, file sharing
Resources/Assets.xcassets        Accent + launch background colors
Resources/AppIcons               Legacy loose-PNG app icon (terminal-prompt glyph)
.github/workflows/ios-build.yml  CI: unsigned IPA artifact
scripts/gen_icon.py              One-off app-icon generator (Pillow) — rerun if the icon changes
Sources/
  VoiceAgentApp.swift            @main entry point
  AgentView.swift                THE screen — the only view
  AgentViewModel.swift           Turn-loop state machine (idle → listening → thinking → answering)
  Design/Theme.swift             Terminal palette + type tokens
  Components/                   TranscriptView, SourceChipView, CaretView, LevelMeterView, button styles
  Speech/                        DictationController (STT + barge-in watch), VoiceProvider + two
                                 implementations, AudioSession
  Corpus/                       CorpusStore (Drive bookmark + scanning), TextExtractor, Chunker,
                                 EmbeddingIndex, Retriever
  Agent/                        ClaudeClient (raw SSE streaming), SystemPrompt, SourceTracker
  Storage/                      Keychain (API keys), AppSettings (small non-secret prefs)
  Settings/SettingsSheet.swift   The one settings surface — a sheet, not a screen
```

## Privacy summary

- **Speech-to-text**: on-device (`SFSpeechRecognizer`, on-device recognition where the locale
  supports it). Nothing sent anywhere for this step.
- **Your documents**: live in your own Google Drive (or a local sandbox folder). Only the
  retrieved excerpts relevant to a given question are sent to Anthropic with that question — never
  whole documents, never your whole folder.
- **Every answer**: a call to the Claude API. Question text + retrieved excerpts leave the device.
- **Web search**: when the model decides your folder doesn't answer the question, the search query
  leaves the device via Anthropic's `web_search` tool.
- **Voice**: on-device by default (nothing leaves the device for speech output). Entering an
  ElevenLabs key sends the text being spoken to ElevenLabs for synthesis.
- **API keys**: stored in the iOS Keychain, never in source, never in `UserDefaults`.
