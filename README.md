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
  synthetic. This is what you get with no Breeze key/voice ID entered, or with only one of the two.
- **Breeze (opt-in):** paste an API key **and** a voice ID in **Settings** (long-press the header,
  or tap the first-launch note) and the app switches to the [Breeze Blue](https://breezeblue.ai)
  text-to-speech API. Unlike some providers, Breeze has no "default voice" — its endpoint requires
  a specific voice ID in the URL, so both fields are needed together. This is the closest practical
  stand-in for a natural voice, not a claim of matching any specific product's voice.

### This app is not fully local

Every answer is a Claude API call (`claude-opus-5`). Speech-to-text stays entirely on-device, and
your documents live in your own iCloud Drive (or the local sandbox fallback) — but **the question
text and the retrieved excerpts from your documents are sent to Anthropic** on every turn, and
**web search queries leave the device** whenever the agent decides your folder doesn't have the
answer. There's a one-line version of this on first launch; this is the full version.

---

## Setup

You need, in order:

1. **An Anthropic API key** — get one at [console.anthropic.com](https://console.anthropic.com).
   Required; nothing works without it.
2. **A documents folder, bridged through iCloud Drive** (see below) — optional in the sense that the
   app runs without it (falling back to an empty local folder), but the whole point of the app is
   moot without it.
3. **A Breeze API key and voice ID** (optional) — get both at [breezeblue.ai](https://breezeblue.ai)
   if you want the more natural voice. The key starts with `brz_`, voice IDs with `voc_` — pick a
   voice from your Breeze account and copy its ID; there's no "just use the default" option.

All of this is entered in the same place: **Settings**, opened by long-pressing the header or
tapping the note under the controls on first launch.

### The iCloud Drive folder bridge (Windows ↔ iPhone, no Mac needed)

The developer's PC is Windows, and iOS has no way to read a Windows folder directly. The bridge is
iCloud Drive — built into iOS already, and reachable from Windows via Apple's own desktop client:

1. **On your PC**, install [iCloud for Windows](https://support.apple.com/HT204283) if you don't
   have it, sign in with the same Apple ID you use on your iPhone, and make sure **iCloud Drive**
   is turned on in its settings. Then create a folder named **`Voice Agent`** somewhere inside the
   **iCloud Drive** folder that appears in File Explorer. Drop your documents in there — PDFs,
   `.txt`, `.md`, `.csv`, `.rtf` are all read. Scanned/image-only PDFs (no embedded text layer —
   common output from a scanner or camera-scan app) are handled too, via on-device OCR
   (`Vision`/`VNRecognizeTextRequest`) — no network, no cost, same on-device story as speech-to-text.
   (`.docx` isn't supported — iOS has no built-in OOXML reader, and reading one by hand would mean
   unzipping the file and parsing its XML, which needs a real archive library. Save Word docs as
   `.rtf` or `.txt` instead.)
2. **On your iPhone**, confirm iCloud Drive is on: **Settings → [your name] → iCloud → iCloud
   Drive**. Nothing else to install — unlike a third-party provider, iCloud Drive is already a
   location the Files app can browse on every iPhone signed into an Apple ID.
3. **In Voice Agent**, open Settings and tap **"Pick (or create) your Voice Agent folder."** This
   opens the system Files picker — navigate to **iCloud Drive → Voice Agent** (the same folder from
   step 1) and select it. The app remembers this folder from then on (a security-scoped bookmark,
   not a copy) — you won't need to pick it again unless you reinstall.
4. From then on, drop a new file into that folder on your PC, and it'll show up in the app's index
   the next time you **foreground the app or tap the header to rescan**. There's no instant live
   sync — a rescan is the trigger rather than something automatic firing the moment a file lands.
5. A freshly-synced file can briefly exist as a cloud-only placeholder (the small cloud icon you
   sometimes see in Files) before iOS has actually downloaded it to the phone. The app now detects
   this, kicks off the download itself, and — instead of silently skipping the file or miscounting
   it as indexed — shows a note like `filename.pdf (still downloading from iCloud — try again
   shortly)` above the source chip. Rescan a few seconds later and it'll pick it up normally.
6. The **`+`** button on the main screen does the reverse: pick a file on your phone, and it gets
   copied into the same iCloud folder, syncing back to your PC.

**The honest tradeoff:** your documents pass through Apple's iCloud sync infrastructure rather than
staying fully local, which is the price of a folder that's genuinely live on both a Windows PC and
an iPhone without a Mac in the loop. Unlike the earlier Google Drive version of this bridge, though,
this needs no new account at all — you already have the Apple ID this uses, from AltStore signing
the app in the first place. The app itself still creates no account of its own — it only reads a
folder the OS's Files app already has access to, via a standard document picker and a
security-scoped bookmark.

If you skip the folder pick entirely, the app uses an empty local folder in its own sandbox
instead (also reachable via the Files app, since file sharing is enabled) — everything still runs,
there's just nothing to be grounded in until you either pick the iCloud folder or use **`+`** to add
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
  Corpus/                       CorpusStore (iCloud bookmark + scanning), TextExtractor, Chunker,
                                 EmbeddingIndex, Retriever
  Agent/                        ClaudeClient (raw SSE streaming), SystemPrompt, SourceTracker
  Storage/                      Keychain (API keys), AppSettings (small non-secret prefs)
  Settings/SettingsSheet.swift   The one settings surface — a sheet, not a screen
```

## Privacy summary

- **Speech-to-text**: on-device (`SFSpeechRecognizer`, on-device recognition where the locale
  supports it). Nothing sent anywhere for this step.
- **Your documents**: live in your own iCloud Drive (or a local sandbox folder). Only the
  retrieved excerpts relevant to a given question are sent to Anthropic with that question — never
  whole documents, never your whole folder.
- **Every answer**: a call to the Claude API. Question text + retrieved excerpts leave the device.
- **Web search**: when the model decides your folder doesn't answer the question, the search query
  leaves the device via Anthropic's `web_search` tool.
- **Voice**: on-device by default (nothing leaves the device for speech output). Entering a
  Breeze key and voice ID sends the text being spoken to Breeze (breezeblue.ai) for synthesis.
- **API keys**: stored in the iOS Keychain, never in source, never in `UserDefaults`.
