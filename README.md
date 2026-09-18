# Tinycast — kmplngj’s fork

Personal fork of [abue-ammar/tinycast](https://github.com/abue-ammar/tinycast).
The only fork-specific feature is portable JSON settings export and folder sync.
Build this fork from source using [the development guide](docs/development.md);
upstream downloads do not include this feature.

## Fork feature: JSON configuration for sync

Choose **Settings → Backup → Configuration location** to enable a portable `settings.json`:

| Location | Behavior |
| --- | --- |
| **This Mac — current storage** | Default native storage; folder sync is off. |
| **Dotfiles folder** | `~/.config/tinycast/settings.json`, using an absolute `XDG_CONFIG_HOME` when available. Dev and beta use distinct preset folders. |
| **Custom folder…** | Choose a directory in a config repository or a folder managed by your sync service. |

Portable UI changes save automatically. Valid external edits reload while Tinycast is running,
including changes pulled with yadm or Git. Tinycast handles the local file; your existing tool handles
commits, pushes, pulls and transport between Macs.

The uncompressed folder follows the `.tinycast` backup’s `settings.json` naming and uses matching
fields such as `customCommands`, `hotkeys`, `windowLayouts` and `launcherAliases`. Its versioned sync
contract adds stable IDs, deterministic formatting and explicit deletion rules;
[the mapping documents each difference](docs/features/configuration.md#relationship-to-a-tinycast-backup).

Portable settings include appearance and launcher preferences, favorites, hidden items, aliases,
shortcuts, custom commands, quicklinks and window layout definitions. JSON uses stable IDs and
predictable formatting for readable diffs. Incoming shell commands and their bindings require local
review; conflicting edits pause shared writes and retain local recovery copies.

**Getting started:** choose a folder, review its resolved path, then use the existing folder settings
or explicitly initialize it from this Mac. Track `settings.json` in your config repository and select
the corresponding local folder once on each Mac. The Debug build uses `tinycast-dev` for its dotfiles
preset. Returning to **This Mac** keeps the applied values and leaves the shared file intact.

The existing **`.tinycast` backup format remains available**, including associated files such as
clipboard images when selected for export. Automatic JSON configuration sync covers portable
settings only. Clipboard/chat history, notes, snippets, credentials, AI/MCP configuration, extension
data, permissions and machine-specific paths remain local. Those categories are never written to
the selected folder; exclusion does not depend on `.gitignore` or the sync provider. Optional data
sync is not implemented. Review manually authored command text
and URLs before sharing them; they can contain private information.

See the [setup guide, exact portable coverage and yadm walkthrough](docs/features/configuration.md),
[example settings.json](docs/examples/settings.json), and
[validation report with UI evidence](docs/validation/configuration/README.md).
Local build, automated and UI checks are recorded there. Two-Mac/provider testing and the full
memory/leak validation remain outstanding; simultaneous edits are not guaranteed to merge without
conflicts.



**A tiny, fully native macOS launcher. One hotkey, everything you reach for all day, under 100 MB of
RAM.**

<p align="center">
  <a href="https://github.com/abue-ammar/tinycast/releases/latest">
    <img alt="Latest release"
         src="https://img.shields.io/github/v/release/abue-ammar/tinycast?sort=semver&style=flat&label=release&color=1F6FEB"></a>
  <img alt="Swift 6.0"
       src="https://img.shields.io/badge/Swift-6.0-F05138?style=flat&logo=swift&logoColor=white">
  <img alt="macOS 26 or later"
       src="https://img.shields.io/badge/macOS-26%2B-000000?style=flat&logo=apple&logoColor=white">
  <a href="LICENSE">
    <img alt="License: AGPL-3.0"
         src="https://img.shields.io/badge/License-AGPL--3.0-3DA639?style=flat"></a>
  <a href="https://discord.gg/v2Eeb4QQy3">
    <img alt="Join the Tinycast Discord"
         src="https://img.shields.io/badge/Discord-Join-5865F2?style=flat&logo=discord&logoColor=white"></a>
  <a href="https://buy.polar.sh/polar_cl_NDVFC20DKQpLcNawsh97QzbARBXD3WNn8v35R0mbJmT">
    <img alt="Support Tinycast"
         src="https://img.shields.io/badge/Support-Tip%20the%20dev-EA4AAA?style=flat&logo=polar&logoColor=white"></a>
</p>

SwiftUI and AppKit, **zero third-party dependencies**, no Electron and no telemetry. It also **runs
real Raycast extensions**, rendered as native SwiftUI. Free, open source, and staying that way.

For anything private, email [iabueammar@gmail.com](mailto:iabueammar@gmail.com).

<p align="center">
  <img src="docs/screenshot.png" alt="Tinycast command palette" width="720">
</p>

## Support

Tinycast is **free, and it stays that way**. If it earns a place in your daily flow, a one-off tip helps
keep it actively maintained. GitHub Sponsors isn't available in my country, so please support here:

<p align="center">
  <a href="https://buy.polar.sh/polar_cl_NDVFC20DKQpLcNawsh97QzbARBXD3WNn8v35R0mbJmT">
    <img alt="Support Tinycast" width="188" height="44" src="docs/support-button.svg"></a><br>
  <sub>Payments are handled securely by <a href="https://polar.sh">Polar.sh</a>.</sub>
</p>

## Features

- **App launcher** — fuzzy-search and launch anything, pin favorites, see what's running, quit an app
  or every app at once.
- **Global hotkey** — one shortcut summons the palette from anywhere.
- **Per-app hotkeys** — bind a key to an app; press it to toggle (focus/hide).
- **Search Files** — open files and folders from the folders you choose, through Spotlight, with no
  index of our own.
- **Dictionary** — look a word up with the Define Word command, or define whatever you typed from the
  launcher's fallbacks, read from the Mac's own dictionaries.
- **Clipboard history** — text and images, searchable, pasted back into the app you were using.
- **Calculator** — do math, unit, live currency and crypto conversions inline, right in the palette.
- **Quicklinks** — turn a URL, search, file or deeplink into a command, with placeholders for typed
  input, the clipboard or the date.
- **Apple Shortcuts** — search and run the shortcuts you built in the Shortcuts app, with aliases and
  global hotkeys.
- **Snippets** — reusable Markdown templates with dynamic placeholders, arguments, nested references
  and optional keyword expansion.
- **Custom commands** — run named shell commands through fuzzy search or their own global hotkeys.
- **Window management** — 34 Rectangle-style actions: halves, quarters, thirds, sizing, nudging,
  display moves, fullscreen and Spaces.
- **System actions** — lock, sleep, restart, empty trash, toggle appearance, Bluetooth, mute, hidden
  files, and more.
- **Calendar and meetings** — your next meeting on the empty palette and in the menu bar, one key to
  join it, or let it join itself.
- **Notes** — an unlimited collection of plain Markdown files in one floating editor, searchable from
  the palette and rendered as you write.
- **Emoji picker** — a searchable emoji grid, one keystroke away.
- **AI chat** — use your own key or an installed AI account, chat from the palette. Off out of the box, like every AI feature.
- **Quick Actions** — fix grammar, rewrite, translate or summarize the selected text in any app.
- **Raycast extensions** — run the ones you already have natively, rendered as SwiftUI.
- **Backup and import** — export your settings to a file, or import your setup from Raycast.

## Install

First, add the tap:

```sh
brew trust --tap abue-ammar/tinycast   # required for third-party taps
brew tap abue-ammar/tinycast
```

Then run the one line that matches your Mac:

| Your Mac                         | Install                                  |
| -------------------------------- | ---------------------------------------- |
| Apple silicon, macOS 26 or newer | `brew install --cask tinycast`           |
| Intel, macOS 26                  | `brew install --cask tinycast-universal` |

Not sure which you have? **Apple menu → About This Mac.** Homebrew checks too, and refuses the
wrong one.

Want early builds? `brew install --cask tinycast@beta` puts `Tinycast Beta.app` beside the stable
app, with its own settings and permissions. Apple silicon, macOS 26+.

Homebrew clears the macOS quarantine flag on every install and update, so there is nothing else to
run. Downloading a DMG from [Releases](https://github.com/abue-ammar/tinycast/releases) instead?
Tinycast is self-signed, so clear the flag once:
`xattr -dr com.apple.quarantine "/Applications/Tinycast.app"`.

## Permissions

**Accessibility** — needed when Tinycast pastes or expands text into another app, and the only
permission snippet keyword expansion needs. You're prompted when you first use a feature that needs
it; grant access in **System Settings → Privacy & Security → Accessibility**. Snippets ship
disabled, and keystrokes are matched locally, never stored and never sent anywhere.

## Using it

1. Open **Settings → General** and record a global shortcut to summon Tinycast.
2. Press it anywhere → the palette floats in. Type to filter, **↵** to launch.
3. **Tab** switches between Apps and Clipboard; **↑/↓** move, **Esc** dismisses.
4. **Settings → Shortcuts** — search an app or custom command and record a global shortcut.
5. **Settings → Snippets** — enable the feature, then create templates with expansion keywords.

## Building from source

See **[docs/development.md](docs/development.md)** for the toolchain, build, packaging, release and
website workflows. **[docs/](docs/README.md)** indexes everything else — architecture, engineering
standards, the design system and one document per feature.

## Contributing

> [!IMPORTANT]
> **Open an issue before you write code — this is mandatory.** Get the bug or the feature agreed on
> first; discussing it in the issue (or on [Discord](https://discord.gg/v2Eeb4QQy3)) is strongly
> encouraged. A PR that doesn't close an issue marked `approved` is closed automatically however good
> the patch is, and the work is wasted. Docs-only fixes are the one exception.
>
> Tinycast's feature set is deliberately closed, and "another launcher has it" is not a reason on its
> own. Ask whether a feature is wanted before you ask for it.

Read **[CONTRIBUTING.md](CONTRIBUTING.md)** first — it covers the memory budget every PR is held to,
the before/after video requirement for visual changes, and why features get declined. Every PR fills
in the **[pull request template](.github/PULL_REQUEST_TEMPLATE.md)**. Security issues go through
[SECURITY.md](SECURITY.md), not the issue tracker.

Questions, ideas, or just want to follow along? **[Join the Discord](https://discord.gg/v2Eeb4QQy3)**.

## License

[AGPL-3.0](LICENSE)
