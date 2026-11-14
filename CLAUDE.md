# OpHack

A small AI widget that lives on the desktop. It can see what is on the screen and, when the user clicks, translates or simplifies the content they are looking at.

The product name shown to users is **Easy Peasy**, and the action button is **Peasify**.

## Commands

- `swift build` builds the project.
- `swift run EasyPeasy` launches the widget as a bare binary (it borrows the Terminal's permissions).
- `scripts/bundle.sh` builds `build/EasyPeasy.app` (bundle ID `com.easypeasy.widget`, ad-hoc signed); `open build/EasyPeasy.app` runs it as a real app with its own Automation permission. The ad-hoc signature changes on every build, so macOS may ask for permissions again after a rebuild.
- `.build/debug/EasyPeasy --self-test` runs Peasify once, prints the outcome (never the page text) and exits.
- Quit from the leaf icon in the menu bar, or right-click the widget.

## Product behaviour

- **Always-available widget**: a small floating window that stays on top of other apps and out of the way until needed.
- **Peasify rewrites the page in place.** Clicking Peasify translates or simplifies the text of the webpage open in the user's browser and replaces it directly in the page's HTML, so the user keeps reading the same page. There is no separate result window.
- **Unpeasify undoes it.** Once the page has been changed, the button reads Unpeasify and turns red; clicking it restores the original text exactly and the button returns to green Peasify.
- **Two modes**, chosen under the button:
  - **Translate** into the language picked in the dropdown.
  - **Simplify** hard English into easier English at the picked level.
- **Act on click**: nothing is read or sent to the AI until the user clicks.

## Design principles

- **Stay small.** This is a widget, not a full app. Prefer one obvious action over menus and settings.
- **Fast to answer.** The user is mid-task; the delay between click and result matters more than extra features.
- **Privacy first.** Page content is sensitive. Read it only on click, send only what the action requires, and never store or log page text.
- **Clear about permissions.** The tool needs macOS Automation permission for the browser, and the browser's "Allow JavaScript from Apple Events" setting. Explain each plainly in the status line when it is missing.

## Platform and stack

- **Native macOS app for Apple Silicon (arm64) only.** No Intel build, no Windows or Linux, no cross-platform wrappers such as Electron or Tauri.
- **Minimum macOS version is 14.**
- **Swift**, with SwiftUI for the widget UI and AppKit where SwiftUI falls short (for example a floating, always-on-top `NSPanel`).
- **Built with Swift Package Manager**, because only the Command Line Tools are installed (no Xcode).
- **Avoid Swift macros** such as `#Preview` and `@Observable`; they need full Xcode.
- A properly signed `.app` (Developer ID, stable permission across builds) will require Xcode later; `scripts/bundle.sh` makes an ad-hoc signed one for now.
- **Page access is JavaScript injected into the browser's front tab through AppleScript** (`NSAppleScript`). Screen capture and OCR are not used; do not reintroduce them.
- Prefer Apple frameworks over third-party dependencies.
- Build for `arm64` only (`ARCHS = arm64`); do not produce universal binaries.

## Code layout

Swift package `Package.swift`, target `EasyPeasy`, sources in `Sources/EasyPeasy/`:

- `main.swift`: entry point; starts the app.
- `AppDelegate.swift`: app setup, no Dock icon, menu bar leaf icon with "Set API Key…", "Move Widget to Bottom of Screen" and Quit.
- `WidgetPanel.swift`: borderless floating `NSPanel`; draggable by its background, remembers its position.
- `WidgetView.swift`: SwiftUI layout of the widget (logo, name, Peasify button, mode picker).
- `WidgetModel.swift`: widget state (mode, language, level, status line, whether the page is peasified) and the button's Peasify / Unpeasify logic.
- `Peasifier.swift`: the orchestrator. Collects the page's text segments, sends them to the AI in batches (up to 3 at once), writes each rewritten segment back as it streams in, and restores the page on Unpeasify.
- `BrowserBridge.swift`: finds the frontmost browser (Safari, Chrome, Arc, Edge, Brave) and runs JavaScript in its front tab via AppleScript.
- `PageScripts.swift`: the JavaScript that runs in the page: collect text nodes and remember the originals, apply replacements, restore.
- `PromptBuilder.swift`: the system prompt and per-batch message, plus the parser for the `[[n]] text` line format the model replies in.
- `OpenRouterClient.swift`: raw HTTP streaming client for OpenRouter's OpenAI-compatible chat completions API.
- `APIKeyStore.swift`: the user's OpenRouter API key in the macOS Keychain (development fallbacks: the `OPENROUTER_API_KEY` env var, then a git-ignored `.env` in the project root; `.env.example` is the template) and the "Set API Key…" dialog.
- `OptionMenu.swift`: the dropdown row under the mode picker; shows Language in Translate mode and Level in Simplify mode.
- `PeaLogo.swift`: the pea-pod logo.
- `ModePicker.swift`: the two-option Translate / Simplify picker.

## AI backend

- **Provider:** OpenRouter (`https://openrouter.ai/api/v1/chat/completions`, `Authorization: Bearer` key), streamed. The user chose OpenRouter; do not switch the client to a provider-specific API.
- **Model:** `OPENROUTER_MODEL` in `.env` or the environment; default `anthropic/claude-opus-5.5`. Any OpenRouter model slug works.
- Requests send `reasoning: {effort: "low"}` because the user is waiting on a widget.
- **Simplify levels** (product requirement): Foreigner = 1st grade English, Beginner = 4th grade, Intermediate = 7th grade.
- **Segment format:** the page is sent as numbered text segments, one per line (`[[12]] text`), and the model returns the same numbers with rewritten text. One segment is one text node in the page, so links, formatting and layout survive.
- **Whole page, not a summary.** Every text segment is rewritten; nothing is cut short silently.
- **API key:** supplied by the user through "Set API Key…" in the leaf menu and kept in the Keychain, or for development in the git-ignored `.env` file. Never put a key in the repository, in UserDefaults or in logs.
- **Privacy:** page text is sent to OpenRouter (and the model provider behind it) only when the user clicks Peasify; it is never written to disk or logged.

## Status

In-place Peasify / Unpeasify is built. Known limits: it needs a supported browser in front with "Allow JavaScript from Apple Events" turned on; text inside iframes is not touched; navigating away discards the page's saved originals.

## Working conventions

- Keep API keys out of the repository; read them from the environment or the OS keychain.
- Update this file when a decision above is made or a convention is established.
