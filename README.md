# Voice Agent

A single-screen iOS app: tap once, talk, and have an ongoing conversation with an agent that
remembers what you tell it and gets to know you over time — across separate sessions, not just
within one. It learns in the background as you talk, asks about you when it makes sense to, and
can still check the web for anything outside its own knowledge, saying so out loud when it does.

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
everything it remembers about you lives only in this app's local storage — but **the question text
and what it currently remembers about you are sent to Anthropic** on every turn (it needs that
context to actually use what it's learned), and **web search queries leave the device** whenever
the agent decides it needs to look something up. There's a one-line version of this on first
launch; this is the full version.

---

## Setup

You need, in order:

1. **An Anthropic API key** — get one at [console.anthropic.com](https://console.anthropic.com).
   Required; nothing works without it.
2. **A Breeze API key and voice ID** (optional) — get both at [breezeblue.ai](https://breezeblue.ai)
   if you want the more natural voice. The key starts with `brz_`, voice IDs with `voc_` — pick a
   voice from your Breeze account and copy its ID; there's no "just use the default" option.

Both are entered in the same place: **Settings**, opened by long-pressing the header or tapping
the note under the controls on first launch. That same screen also shows everything it's learned
about you so far, with the ability to forget any of it, or all of it.

---

## How the memory actually works

1. **Every request includes what's currently known.** `MemoryStore` holds a flat, growing list of
   short facts, persisted to a local JSON file. `SystemPrompt.swift` folds the current list into
   the system prompt on every single call — a fact learned mid-conversation is available on the
   very next turn, not just the next app launch.
2. **Learning happens after the spoken answer, not during it.** Once a turn finishes, a second,
   separate, non-streaming call goes to Claude in the background — cheap, tool-free, `effort: low`
   — asking it to name one new durable fact worth remembering from that exchange, if any (a
   preference, a relationship, a job, a goal, a correction to something already known — not small
   talk). This never delays or blocks the spoken answer; by the time it comes back, the agent has
   usually already finished talking. If something new comes back, it's saved locally and a short
   note appears on screen: `Remembered: ...`.
3. **A tool-free follow-up call, not a client-side tool the model invokes mid-answer**, on purpose —
   the main streaming path only has to handle text and `web_search`, keeping its failure modes
   limited to what's already been exercised, rather than adding a full tool-use round-trip loop to
   a path that also has to stay responsive for barge-in.
4. **It asks about you too.** The system prompt doesn't just wait for facts to come up — it's
   instructed to ask genuine, one-at-a-time questions about your life when there's a natural
   opening, leaning into that more when little is known yet and easing off as it learns more.
5. **The source chip** still flips from hidden to amber ("web · N results") the instant the model's
   stream shows it invoking `web_search` — not by guessing from the model's wording. There's no
   more "local vs. web" distinction the way there was when this app was grounded in a document
   folder; the chip now only ever means "this answer involved a web search."
6. **Settings shows the whole list, plainly.** Nothing is hidden or summarized — every fact it's
   stored is listed exactly as saved, swipeable to forget individually, or all at once.

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
Resources/Info.plist             Bundle config, mic/speech usage strings
Resources/Assets.xcassets        Accent + launch background colors
Resources/AppIcons               Legacy loose-PNG app icon (microphone glyph)
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
  Memory/MemoryStore.swift       Persisted facts learned about the person, growing over time
  Agent/                        ClaudeClient (raw SSE streaming + the memory-extraction call),
                                 SystemPrompt, SourceTracker
  Storage/                      Keychain (API keys), AppSettings (small non-secret prefs)
  Settings/SettingsSheet.swift   The one settings surface — a sheet, not a screen
```

## Privacy summary

- **Speech-to-text**: on-device (`SFSpeechRecognizer`, on-device recognition where the locale
  supports it). Nothing sent anywhere for this step.
- **What it remembers about you**: stored only in this app's local storage on your device — never
  synced anywhere. It's sent to Anthropic as context on every turn, though, since that's how the
  agent actually uses it (see below).
- **Every answer**: a call to the Claude API. Question text + the current memory list leave the
  device on every turn.
- **Learning**: a second, separate call after each turn, asking Claude to name any new fact worth
  keeping from that exchange. Same exposure as the main call — the exchange and current memory
  leave the device for this step too.
- **Web search**: when the agent decides it needs to look something up, the search query leaves the
  device via Anthropic's `web_search` tool.
- **Voice**: on-device by default (nothing leaves the device for speech output). Entering a
  Breeze key and voice ID sends the text being spoken to Breeze (breezeblue.ai) for synthesis.
- **API keys**: stored in the iOS Keychain, never in source, never in `UserDefaults`.
