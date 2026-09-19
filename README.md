# TipTour

A macOS menu bar companion with two modes, powered by your own API keys.

| Mode | Shortcut | What it does |
| --- | --- | --- |
| Gemini realtime | Ctrl+Option | Talk about your screen and ask for one desktop action per turn. Press again to stop. |
| JEV text | Ctrl+K | Type a click-based task. JEV chooses from locally detected controls, then TipTour executes and validates each action. |

**JEV is selected by default.** On first launch, choose JEV or Gemini, save that mode’s API key, then grant its permissions. JEV does not require microphone access. You can switch later in **Settings → Models**, which shows only the selected mode’s key field. Keys stay in macOS Keychain. There are no shared keys, hosted key proxies, or keys loaded from other projects.

Shortcuts activate only the selected mode. The primary menu-bar button and welcome hint follow your selection.

## Using TipTour

- Gemini supports clicking, typing, shortcuts, app/URL opening, scrolling, and highlighted text edits. It also supports creating an Apple Notes note from supplied content.
- JEV supports single, double, and right clicks. It reads screen labels and locations from local detection; it cannot see images or generate replacement text. Use Gemini for writing or keyboard actions.
- Press **Escape** in the text panel or click **Stop** to cancel JEV. The loop stops on an uncertain/absent target, an execution pause/failure, or its 12-action limit.
- Hold **Ctrl+Shift** and paint over an area to give Gemini focus context.
- Hold **Ctrl+Option+Command** for the Speak / Type / Highlight shortcut chooser.
- **Auto-click** lets TipTour act. **Point only** lets Gemini indicate where you should click. JEV requires auto-click.

Settings also contains desktop action access, screenshot privacy, permissions, and optional debug visuals. There is no recording, video creation, or image-generation pipeline.

## Privacy and permissions

Gemini receives microphone audio and, when enabled, screenshots. JEV receives your typed task, locally detected labels/locations, and recent action history; screenshots stay local. Both modes use the shared local grounding and action engine.

Accessibility permission is needed to inspect and control apps. macOS Screen Recording / Screen Content permission enables screenshots and local screen detection; it does **not** mean TipTour records videos. Microphone access is only needed for Gemini voice.

## Build

Requires macOS 14.2+ and a current Xcode with Swift support. Open `tiptour-macos.xcodeproj`, select the TipTour scheme, set your signing team, and build/run in Xcode. Package dependencies resolve through Xcode.

Use Xcode for app builds: terminal `xcodebuild` is prohibited by this repository's workflow to preserve the installed app's macOS permissions. Run `scripts/test-jev.sh` for isolated JEV decision tests without installing or launching the app.

## Code

See [source layout](docs/source-layout.md) and [local harness contract](docs/tiptour-agent-contract.md). `main` is the integration branch for both modes; feature branches are temporary PR work.

MIT licensed. See [LICENSE](LICENSE).
