# Configuration folder validation — 2026-09-08

Local implementation against upstream `66b95b2c18756fd7f2a45c1f00a0f3c3f2202321`.
This record is evidence for a proposal, not a claim that every upstream contribution gate is met.
Proposal submitted as [upstream issue #505](https://github.com/abue-ammar/tinycast/issues/505).

## Fork publication checks — 2026-09-09

The fork implementation was updated on top of `17ed8a1` (including the newer Escape-key preference,
Quick Actions optimization, extension refresh and clipboard changes), using an isolated worktree to
preserve unrelated local work. The generated Xcode project was regenerated after integration.

- Debug build passed with no new compiler warnings; the known App Intents metadata warning remains.
- All **64 standalone harnesses passed**. The two configuration harnesses cover the published
  backup-aligned field names and reject the earlier unpublished aliases and data-category injection.
- The built-runtime integration fixture passed with the actual AppCore/stores: portable settings
  and authored command/quicklink fields match a gathered `SettingsBackup`; the Escape-key preference
  round-trips; notes/snippet/image fixtures and learning remain local; activation writes only
  `settings.json`; optional archive directories and `manifest.json` placed beside it are ignored and
  left unchanged through subsequent writes.
- Lint, Model import purity and whitespace checks passed. No new Configuration lint warnings.
- Computer Use checked the final Backup pane and Reload action in a fresh profile. The
  [local-data notice](settings-data-boundary.jpg) makes the exclusion visible alongside normal backup
  category controls. No optional service or global shortcut engine was started by this fixture.

Only `settings.json` is authoritative. Optional data sync is not implemented, and no archive packing
or extraction behavior was changed. The physical-Mac/provider and memory/leak limitations below
still apply. The following sections retain the original September 8 evidence and measurements.

## Automated checks

- Debug Xcode build passed using Xcode from `/Volumes/space/Applications/Xcode.app`.
  No Swift compiler warnings were added. The App Intents metadata extraction warning is also in
  the clean upstream baseline build.
- All 61 standalone harnesses passed, including schema/coverage and filesystem reconciliation.
- The built-runtime fixture passed: folder initialization/adoption, UI-model export, external
  reload within two seconds, commands/review, quicklinks/pins, aliases/favorites, layout roles,
  bindings/deletions, unsupported targets, backup import, malformed input, same-field conflict,
  offline pending edits/reconnection and returning to local storage.
- Lint passed without warnings in the new Configuration sources. Existing unrelated repository
  warnings remain. Model-layer import purity and `git diff --check` passed.

The standalone filesystem tests use two independent persisted app-state instances, not two Macs.
The runtime fixture uses the shipped coordinator and stores in fresh bundle-ID profiles. Global
shortcut engines and optional services are deliberately not started by that fixture. Carbon
registration on a full app session and display placement on multiple monitors remain manual checks.

## Computer Use

The actual SwiftUI settings window was driven through macOS accessibility and native UI actions,
with synthetic data under a dedicated `com.tinycast.configuration-test.<uuid>` profile. The user's
installed Tinycast preferences and selected configuration location were not changed.

| Action | Observed result |
| --- | --- |
| Return to This Mac | Folder left intact; local values kept. |
| Choose Dotfiles folder | Resolved channel-specific path previewed; cancellation created no shared file. |
| Choose Custom folder | Native directory picker selected an existing synthetic folder. |
| Use Folder Settings | Status became Current and existing portable settings applied. |
| Toggle Compact Mode in General | `settings.json` changed automatically. |
| Atomically change Compact Mode externally | The visible switch updated without Reload or restart. |
| Search for configuration | Search result navigated to Configuration location in Backup. |
| Write malformed JSON/Git markers | Invalid configuration; last valid values kept and writes paused. |
| Add a synthetic shell command externally | Review required; before/after definition and binding shown. |
| Approve the command revision | Status returned to Current; no command executed and local capability stayed off. |
| Change appearance locally and differently in the file | Conflict identified `settings/appearance`. |
| Choose Use Folder Version | Status returned to Current with the folder value. |

[Final current pane](final-current.jpg), [earlier current pane](backup-current.jpg), [conflict controls](conflict.jpg), and
[before/after video](before-after.mp4) are captured from real windows. Video: upstream on the left,
local implementation on the right; both 860 × 700, General → Backup navigation. It combines repeated
Computer Use captures at 10 frames/second for review, rather than measuring animation timing.
Footage predates the final accessible menu label and more detailed difference summaries. A fresh
final-build fixture subsequently passed its runtime checks and Computer Use verified the accessible
location menu, resolved dotfiles preview and cancellation back to Current.

## Memory and leaks — not a passed gate

Debug isolated Settings fixtures were measured with `ps` and Apple's `leaks`. They instantiate the
real AppCore and settings views, but do not start normal background services. The UI runs were not
identical workloads and these samples are not peak-memory or regression attribution measurements.

| Fixture | Sampled RSS with Settings used/open | `leaks` report |
| --- | --- | --- |
| Upstream baseline | 154,704 KiB | 1,019 allocations, 48,336 bytes |
| Local implementation after the broader UI sweep | 120,128 KiB | 708 allocations, 32,096 bytes |

Both exceed the contribution's 100 MB ceiling in these samples. Both leak reports warn that the
ad-hoc process is not debuggable and show framework-owned allocations. These observations do **not**
establish zero leaks, prove every report is harmless, or isolate the feature's memory cost. A
controlled signed Release/Instruments comparison, idle/peak measurements and lifecycle investigation
are required before a PR. No zero-leak or under-100-MB claim is made.

## Remaining manual acceptance work

- Two physical Macs: UI edit → yadm commit/push/pull → automatic update, both directions.
- Actual sleep/wake and external-volume/cloud-provider disconnect/reconnect. Synthetic filesystem
  replacement/reconnection passed; that does not validate every provider's coordination behavior.
- Real shortcut registration/unregistration and missing-app availability in a full app session.
- Multi-monitor layout execution and local display-role mapping review.
- A full signed app memory/leak sweep and maintainer review of the proposed scope/contract.

The final prewrite check cannot make an atomic transaction with an uncoordinated Git/editor process.
Provider conflicts and not-yet-transported remote edits still require user resolution. No transport
commands, issue comments, PR, source push or deployment are performed by this test workflow.
