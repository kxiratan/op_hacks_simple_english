# OpHack

A small AI widget that lives on the desktop. It can see what is on the screen and, when the user clicks, translates or simplifies the content they are looking at.

## Product behaviour

- **Always-available widget**: a small floating window that stays on top of other apps and out of the way until needed.
- **Screen capture**: the tool captures the screen (or a region of it) so the AI can read what the user is looking at.
- **Act on click**: nothing is sent to the AI until the user clicks. A click triggers one of two actions on the visible content:
  - **Translate** it into the user's language.
  - **Simplify** it into plainer, shorter wording.
- **Result shown in place**: the answer appears in the widget, close to the content, without making the user switch apps.

## Design principles

- **Stay small.** This is a widget, not a full app. Prefer one obvious action over menus and settings.
- **Fast to answer.** The user is mid-task; the delay between click and result matters more than extra features.
- **Privacy first.** Screen content is sensitive. Capture only when needed, send only what the action requires, and do not store screenshots or results on disk unless the user asks.
- **Clear about permissions.** The tool needs the operating system's screen recording permission. Ask for it with a plain explanation and handle the case where it is refused.

## Status

New project; no code yet. The following are not decided, so do not assume them:

- Tech stack (Electron, Tauri or native Swift)
- Target platforms (development is on macOS)
- AI provider and model
- Whether capture is the full screen, the active window or a user-selected region
- Whether capture is continuous or a single screenshot at click time

When one of these is decided, record it here along with the build, run and test commands.

## Working conventions

- Keep API keys out of the repository; read them from the environment or the OS keychain.
- Update this file when a decision above is made or a convention is established.
