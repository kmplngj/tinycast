# Automatic configuration folder

Configuration folder mode is opt-in under **Settings → Backup → Configuration location**.
Native UserDefaults and Application Support remain the default. No system preferences plist is
moved, edited directly, or symlinked. Tinycast reads and writes a local file; yadm/Git or the folder
provider transports it. No account, transport scheduler, server, or cloud SDK is involved.

## Invariants

- `AppCore` owns one `ConfigurationCoordinator`. It serializes reconciliation and disk operations.
- Only a validated `PortableConfiguration` can reach the runtime adapter. The archive importer is
  not the sync decoder; imported runtime changes enter as ordinary local edits.
- The folder choice, accepted base, pending edits, candidate bytes, approvals and recovery live under
  `Application Support/<bundle-id>/configuration/`, never beside the shared document.
- Incoming executable definitions and bindings require approval for their exact content revision.
  Loading never runs a command, enables Custom Commands, or grants other local consent.
- A missing file after activation never authorizes recreation. Invalid, incompatible, unavailable
  and conflicting versions retain the last valid runtime state and pause shared writes.

## Setup

Choose **Dotfiles folder** or **Custom folder…**. The preset uses a nonempty absolute
`XDG_CONFIG_HOME`, falling back to `~/.config`. Finder-launched apps often have no shell environment;
always inspect the resolved path shown before **Use This Folder**. Stable uses `tinycast`, Dev
uses `tinycast-dev`, and beta uses `tinycast-beta`; other bundle IDs have their own suffix.

An empty destination is initialized only after **Use This Folder**. An existing valid document
shows differences and offers **Use Folder Settings** or **Replace With This Mac’s Settings**.
Replacement requires that explicit choice and saves the old bytes in local recovery. Reading an
existing file at startup never overwrites it. A folder change follows the same process and leaves
the old directory intact. **This Mac — current storage** keeps the applied values locally, stops
observation and writing, and leaves the shared file intact.

This distribution has `com.apple.security.app-sandbox = false`; the native directory picker needs
no security-scoped bookmark. A sandboxed distribution needs a separate reviewed access lifecycle
before claiming support. A symlinked selected directory is supported, including changing its target.
A symlinked `settings.json` is refused: choose the target file’s parent directory instead.

**Reveal in Finder**, **Reload** and status are available while folder mode is active. Invalid
activation leaves the previous mode active. Status descriptions say why writes are paused; controls
remain editable and changes are retained in the local journal. Recovery is accessible from the pane.

## Relationship to a `.tinycast` backup

Folder sync uses the backup's `settings.json` filename and top-level settings names. It stores an
uncompressed, readable portable view, with one authoritative document. The existing `.tinycast`
archive remains a full snapshot composed through `BackupComposer` and `BackupBundle`; its encoder,
reader and category choices are unchanged.

| Backup `settings.json` field | Folder field | Deliberate sync difference |
| --- | --- | --- |
| `settings` | `settings` | Same portable scalar names/values; strict allowlist, defaults and consent exclusions. |
| `customCommands` | `customCommands` | Same command record fields; UUID-keyed object instead of an array with embedded IDs. `customCommandOrder` preserves order. |
| `quicklinks` | `quicklinks` | Same authored fields; UUID keys replace embedded IDs, creation time remains local, and `pinnedQuicklinks` replaces pin timestamps. |
| `windowLayouts` | `windowLayouts` | Same authored field names where applicable; UUID maps and `entryOrder` retain identities/order, portable display roles replace hardware records, and creation time stays local. |
| `hotkeys` | `hotkeys` | One map keyed by stable action identity; explicit combo/double-tap fields avoid Swift's synthesized enum representation and make per-binding reconciliation possible. Backup groups bindings by action kind. |
| `favoriteApps` | `favoriteApps` | Same ordered identity list, filtered to portable targets. |
| `hiddenLauncherItems`, `hiddenLauncherKinds` | Same names | Membership objects (`identity: true`) instead of unordered arrays, so independent visibility edits can merge. |
| `launcherAliases` | `launcherAliases` | Same identity-to-text map, filtered to portable targets. |
| No equivalent | `schemaVersion` | Independent sync contract; backup format numbers do not establish sync compatibility. |

Command and quicklink records use the existing models' Codable encoding and decoding through the
runtime adapter. The integration fixture compares their authored fields and every portable scalar
with a real gathered `SettingsBackup`. Schema validation refuses unexpected new fields until the
allowlist is reviewed. The backup importer's absent-field merge and permissive enum decoding do not
apply to live sync: missing entities delete, omitted bindings unbind, and invalid candidates are held.

`manifest.json` stays an archive concern. Its creation time, app version and counts are snapshot
metadata and would cause needless changes during continuous sync. There is no second mutable sync
manifest to arrive before or after `settings.json`.

### Local data boundary

Only portable configuration is currently supported. Clipboard history/images, notes, snippets and
learning are **not exported into the selected folder**, even if enabled locally. They keep their
native Application Support stores. Their directories are not created there, and existing files in
`clipboard/`, `notes/`, `snippets/`, `learning/` or an archive `manifest.json` are neither imported nor
rewritten by folder sync. They are not deleted either: a destination may contain other user files.

This boundary does not rely on `.gitignore` or a provider-specific ignore file. A sync provider may
transport anything the user places in its folder. Tinycast writes no optional data there by default;
putting an extracted backup in that folder yourself can still share its contents.

There are no category opt-in switches in this version. A future notes/snippets or clipboard feature
must explicitly enable each category on each Mac, preferably with a separate private data folder,
and define stable file identities, deletion/retention, missing-asset handling and conflict rules.
An incoming document must never enable sharing. Learning sync remains deferred until its merge
semantics are useful. Credentials, permissions, bookmarks, approvals and recovery always stay local.

An extracted backup `settings.json` is not a live sync document. Import the original `.tinycast`
archive through Backup, then initialize a separate empty configuration folder. The initial local
prototype's shorter field names (`commands`, `bindings`, `layouts`, etc.) were never published as a
supported schema. They are refused as unknown fields, not silently migrated or overwritten. This
is the first published version 1 contract.

Custom Quick Actions and their shortcuts stay local with the AI feature; folder sync does not
export their prompts, definitions or bindings.

## File contract, version 1

Only `settings.json` belongs in the selected folder. It is UTF-8 JSON, pretty-printed with sorted
object keys, two-space indentation and one trailing newline. Readers accept other valid formatting;
semantic no-ops preserve the original bytes and modification time. Maximum size is 2 MiB, maximum
nesting is 32, a collection has at most 10,000 entries and a string at most 65,536 UTF-8 bytes.
Duplicate JSON keys (including escaped equivalents), wrong types/ranges, unknown fields, unknown
enum values, malformed/partial JSON and Git conflict markers are refused. Unknown fields anywhere
in a supported schema refuse write mode with their location; they are never silently dropped.

`schemaVersion` is required and must equal `1`. Version 1 is the first published fork contract: there
are no older supported versions or fabricated migration formats. Versions 0 and 2+ are rejected
without changing the file. Any future supported migration must explicitly transform the document
and save recovery bytes before rewriting. Sharing a custom folder between channels requires the
same supported schema, independently of application version.

This is a **complete effective document**. Absent scalar settings take the defaults below, absent
collections are empty, missing entities are deleted and absent bindings are unbound. This differs
from the backup importer’s optional-field merge. Object entities use lowercase canonical UUIDs;
app targets use bundle IDs. Unknown built-in action IDs and unavailable apps remain in the document;
unavailable app shortcuts are not registered. Local edits are overlaid onto the authoritative
accepted document so missing runtime targets cannot erase another Mac’s configuration.

| Field | Shape and semantics |
| --- | --- |
| `schemaVersion` | Required integer `1`. |
| `settings` | Object; exact allowlist and defaults below. |
| `customCommands` | UUID-keyed definitions: required `name`, `command`; booleans `isEnabled` (true), `loadsShellEnvironment`, `requiresConfirmation`, `showsConfirmation`, `showsOutput` (all false); `arguments` (empty ordered array of required `name`, optional `isOptional` false); nullable `workingDirectory`, `iconSymbol` (null). |
| `customCommandOrder` | Ordered UUID array, must contain every command exactly once. Required when commands are present. |
| `quicklinks` | UUID-keyed records: required `name`, `link`; nullable `openWithBundleID`, `iconSymbol` (null); `isEnabled` and `showsInRootSearch` (true). |
| `pinnedQuicklinks` | Ordered subset of quicklink UUIDs. Replaces pin timestamps without losing pin order. |
| `windowLayouts` | UUID-keyed records: required `name`, `entries`, `entryOrder`; nullable `iconSymbol` (null); `usesPreferredGap` (true). |
| `windowLayouts/<id>/entries` | UUID-keyed records: required `bundleID`; nullable `argument` (null); `displayRole` (`primary`); `widthFraction` and `heightFraction` (1, range 0…1); `anchor` (`center`, one of top-left/top/top-right/left/center/right/bottom-left/bottom/bottom-right); `offsetX`, `offsetY` (0, ±10,000 points). |
| `windowLayouts/<id>/entryOrder` | Ordered array containing every entry exactly once. A layout must have an entry. |
| `hotkeys` | Target-keyed object. A combo has integer `keyCode` 0…127 and Carbon `modifiers` containing only Command/Shift/Option/Control (256/512/2048/4096). Command, Option or Control is required except for F1…F20. A double tap has `doubleTap`: control/option/shift/command. Unused members are null; do not combine the two forms. |
| `favoriteApps` | Ordered stable launcher identity array. |
| `hiddenLauncherItems`, `hiddenLauncherKinds` | Identity/category-keyed objects with value `true`; omission means visible. |
| `launcherAliases` | Stable launcher identity → nonblank text. |

Binding targets are `togglePalette`, `app:<bundle-id>`, `pane:<bundle-id>`, `command:<action>`,
`system-action:<action>`, `window-command:<action>`, `custom-command:<uuid>`, `quicklink:<uuid>` or
`window-layout:<uuid>`. Launcher identities use bundle IDs and the same command/entity prefixes.
References to authored entities must exist; remove their bindings, aliases, favorites and hidden
entries when deleting them externally. Duplicate names within a collection and shortcut collisions
are invalid. Local extension shortcut collisions also prevent applying the candidate.

Display roles resolve locally at execution: primary is the display at the desktop origin;
secondary and tertiary are the remaining displays in local display order. A disconnected role is
skipped, never redirected by hardware ID. When adopting existing hardware-specific layouts,
connected screens map to these roles; an unknown/disconnected display maps to primary and displays
beyond the third map to tertiary. Review these layouts during adoption. The v1 document supports
three roles; exact hardware selection remains a local editor choice and never enters the file.

Creation dates remain local. Authored command text, paths, layout arguments and URLs are user
content: Tinycast does not claim to detect embedded secrets. Review those values before tracking
or sharing the folder. Only explicitly nullable members above accept null.

## Exact portable preference coverage

All included scalar names and defaults are listed here. They describe presentation and ordinary
launcher behavior, not access permission or installed tool configuration.

| JSON setting | Schema default | Allowed values |
| --- | --- | --- |
| `compactMode` | `false` | Boolean |
| `showFavoritesInCompactMode` | `true` | Boolean |
| `openOnCursorScreen` | `true` | Boolean |
| `paletteDraggable` | `false` | Boolean |
| `customCommandsShowInLauncher` | `true` | Boolean |
| `windowManagementEnabled` | `false` | Boolean |
| `windowManagementShowInLauncher` | `true` | Boolean |
| `windowCycle` | `"off"` | `"off"`, `"sizes"`, `"displays"` |
| `windowLayoutsShowInLauncher` | `true` | Boolean |
| `quicklinksEnabled` | `false` | Boolean |
| `quicklinksShowInLauncher` | `true` | Boolean |
| `quicklinkOpensNewWindow` | `false` | Boolean |
| `quicklinkConfirmsBeforeDelete` | `true` | Boolean |
| `calendarShowInLauncher` | `true` | Boolean |
| `calendarIncludesTomorrow` | `true` | Boolean |
| `menuBarLinkedEventsOnly` | `true` | Boolean |
| `supportReminders` | `true` | Boolean |
| `showInMenuBar` | `true` | Boolean |
| `escapeKeyBehavior` | `navigateBackOrClose` | `navigateBackOrClose`, `closeAndPopToRoot` |
| `appearance` | `"system"` | ["system", "dark", "light"] |
| `paletteTransparency` | `0` | Integer from -100 to 100. |
| `emojiSkinTone` | `"none"` | ["none", "light", "mediumLight", "medium", "mediumDark", "dark"] |
| `quicklinkSelectionFallback` | `"ask"` | ["ask", "clipboard"] |
| `popToRootSeconds` | `0` | [0, 5, 15, 30, 60, 90] |
| `calendarLauncherLimit` | `3` | [0, 1, 3, 5] |
| `joinWindowMinutes` | `5` | [1, 2, 5, 10, 15] |
| `menuBarEvents` | `0` | [0, 2, 5, 10, 30] |
| `calendarMenuBarDisplay` | `0` | [0, 1, 2] |
| `hideCurrentEvent` | `-1` | [-1, 0, 5, 10, 30] |
| `windowGap` | `0` | Integer 0…100 |

Every `AppSettingsKey` is explicitly included or excluded and the harness fails if that coverage
drifts. The following table names each excluded local key, including deliberate differences from
backup coverage. `launchAtLogin` is externally sourced and also remains local. `showInMenuBar` is
externally sourced and portable. Per-entity collections above are reviewed independently of the
backup category.

| Local key | Reason | Difference from backup |
| --- | --- | --- |
| `clipboardEnabled` | Local clipboard capture policy and data. | Backup includes it; continuous sync excludes it. |
| `clipboardTextSearchEnabled` | Text recognition must be enabled on each Mac. | Excluded from backups and continuous sync. |
| `clipboardRetentionDays` | Local clipboard capture policy and data. | Backup includes it; continuous sync excludes it. |
| `clipboardDefaultAction` | Local clipboard capture policy and data. | Backup includes it; continuous sync excludes it. |
| `clipboardDisabledApps` | Local clipboard capture policy and data. | Backup includes it; continuous sync excludes it. |
| `hyperKeyPhysicalKey` | Local physical keyboard remapping and input sources. | Backup includes it; continuous sync excludes it. |
| `hyperKeyIncludesShift` | Local physical keyboard remapping and input sources. | Backup includes it; continuous sync excludes it. |
| `hyperKeyQuickPress` | Local physical keyboard remapping and input sources. | Backup includes it; continuous sync excludes it. |
| `autoSwitchInputSource` | Local physical keyboard remapping and input sources. | Excluded by both. |
| `launcherSearchScopes` | Machine-specific search roots and policy. | Backup includes it; continuous sync excludes it. |
| `fileSearchEnabled` | Machine-specific search roots and policy. | Backup includes it; continuous sync excludes it. |
| `fileSearchScopes` | Machine-specific search roots and policy. | Backup includes it; continuous sync excludes it. |
| `fileSearchIgnorePatterns` | Machine-specific search roots and policy. | Backup includes it; continuous sync excludes it. |
| `palettePosition` | Local window geometry. | Excluded by both. |
| `notesEnabled` | Local notes and snippet data and capability settings. | Backup includes it; continuous sync excludes it. |
| `snippetsEnabled` | Local notes and snippet data and capability settings. | Excluded by both. |
| `snippetsShowInLauncher` | Local notes and snippet data and capability settings. | Backup includes it; continuous sync excludes it. |
| `customCommandsEnabled` | Executing shell commands must be enabled on each Mac. | Backup includes it; continuous sync excludes it. |
| `extensionsEnabled` | Local extension code, registries and toolchain. | Excluded by both. |
| `extensionsShowInLauncher` | Local extension code, registries and toolchain. | Backup includes it; continuous sync excludes it. |
| `extensionPackageManager` | Local extension code, registries and toolchain. | Excluded by both. |
| `extensionRegistries` | Local extension code, registries and toolchain. | Excluded by both. |
| `extensionCustomSearchPaths` | Local extension code, registries and toolchain. | Excluded by both. |
| `calendarEnabled` | Local calendar, unattended actions and camera consent. | Excluded by both. |
| `autoJoinMeetings` | Local calendar, unattended actions and camera consent. | Excluded by both. |
| `autoJoinConfirms` | Local calendar, unattended actions and camera consent. | Backup includes it; continuous sync excludes it. |
| `cameraPreview` | Local calendar, unattended actions and camera consent. | Excluded by both. |
| `aiEnabled` | Local AI connections, credentials, instructions and histories. | Excluded by both. |
| `aiInstalledProviders` | Local AI connections, credentials, instructions and histories. | Excluded by both. |
| `aiConnections` | Local AI connections, credentials, instructions and histories. | Excluded by both. |
| `aiDefaultModel` | Local AI connections, credentials, instructions and histories. | Excluded by both. |
| `aiWebSearch` | Local AI connections, credentials, instructions and histories. | Excluded by both. |
| `aiSystemPrompt` | Local AI connections, credentials, instructions and histories. | Excluded by both. |
| `aiSystemPromptEnabled` | Local AI connections, credentials, instructions and histories. | Excluded by both. |
| `aiRetentionDays` | Local AI connections, credentials, instructions and histories. | Excluded by both. |
| `aiOpensTo` | Local AI connections, credentials, instructions and histories. | Excluded by both. |
| `aiNewChatAfterMinutes` | Local AI connections, credentials, instructions and histories. | Excluded by both. |
| `mcpEnabled` | Local executable servers and credentials. | Excluded by both. |
| `mcpServers` | Local executable servers and credentials. | Excluded by both. |
| `quickActionsEnabled` | Local text delivery consent and AI transformation policy. | Excluded by both. |
| `quickActionModel` | Local text delivery consent and AI transformation policy. | Excluded by both. |
| `quickActionPreviews` | Local text delivery consent and AI transformation policy. | Excluded by both. |
| `quickActionInstructions` | Local text delivery consent and AI transformation policy. | Excluded by both. |
| `quickActionLanguage` | Local text delivery consent and AI transformation policy. | Excluded by both. |
| Launch at login | A local login item. | Backup includes it; sync excludes it. |
| Selected folder, bookmark, approvals, journal, status | Local access and reconciliation metadata. | Not part of the archive schema. |
| Credentials, Keychain, AI/MCP metadata, extension code/data | Local sensitive data and executable sources. | Excluded by both. |
| Clipboard/chat histories, notes, snippets, caches, learned ranking, frequent emoji, calculator history | Runtime or authored data outside portable settings v1. | The archive can carry some histories, notes, snippets and learning as separate categories. |
| Window positions, concrete display UUIDs, search/tool paths | Machine-specific geometry and resources. | Some search roots and layout UUIDs are included by backup; sync uses local roots and display roles. |

## Reconciliation and recovery

Portable runtime changes are observed through the adapter; backup imports explicitly enter the same
coordinator. Shared persistence uses a 350 ms debounce. Normal termination flushes pending work;
durability during use does not depend on quitting. A local journal retains base/local/incoming
snapshots. Distinct local and accepted revisions are recovered by content hash; the most recent
20 distinct files are retained, separately from the journal.

Directory and file vnode observation catches uncoordinated editor/Git writes as well as atomic
replacement. Ancestors of both the selected and resolved directory are observed so replacements
and reconnection can re-arm the file watch. Activation, wake, mount and explicit Reload re-read.
Unavailable locations additionally retry with backoff from 2 to 30 seconds; there is no permanent
fast polling loop. Disk access and watcher descriptor setup run off the main actor.

Every shared write coordinates access with Foundation, re-reads the target and compares with the
bytes it reconciled, writes a temporary sibling and renames on the same filesystem. Initial creation
uses an exclusive filesystem operation. A second check just before replacement narrows the race.

- No pending local edit: apply a valid external change, including deletions, without rewriting it.
- Disjoint edits: three-way merge against the accepted base. Settings fields and different entity
  IDs merge; one authored entity and every ordered array are indivisible in v1.
- Same-field/entity divergence or delete-versus-edit: pause shared writes. **Keep This Mac** or
  **Use Folder Version** makes the choice explicit, or resolve externally and Reload.
- Invalid input, unsupported schema, missing/unwritable file or unavailable folder: retain the
  last valid values, journal local edits and retry when the file changes. Never initialize again.
- Executable changes: hold the candidate and show before/after definitions and bindings. Exact
  locally approved revisions do not prompt on every reload; changes invalidate the approval.

These checks are not distributed transactions. An uncoordinated process can still write between
Tinycast’s final check and rename, and offline Macs cannot see changes their provider has not
transported. Avoid simultaneous edits, exchange changes before editing, and resolve Git/provider
conflicts explicitly. Tinycast never selects a winner by modification time and never removes
provider-generated conflict copies. Recovery is bounded mitigation, not a guarantee of lossless
simultaneous multi-Mac editing.

## yadm walkthrough

1. Enable Dotfiles folder on Mac A and confirm the resolved path. Review `settings.json` for any
   sensitive text you placed in commands or URLs.
2. With yadm already configured, run `yadm add ~/.config/tinycast/settings.json`,
   `yadm commit -m "Track Tinycast portable settings"`, then `yadm push`.
3. On Mac B, run `yadm pull`, select that same local folder once in Tinycast and choose
   **Use Folder Settings**. Review incoming executable revisions on B.
4. Make a portable UI edit on A; inspect `yadm diff`, commit and push. Pull on B. Tinycast should
   apply the valid settled file within two seconds without import or restart. Repeat in reverse.
5. For a conflict, resolve the Git file first or use Tinycast’s conflict actions, then inspect and
   commit the chosen result. Do not use forced replacement as an ordinary pull workflow.

Use the resolved XDG/channel path instead of the stable default in these commands when appropriate.
Tinycast never runs these commands for you.

## Validation

`configuration-test` exercises the real pure schema, coverage, defaults/deletions, strict rejection,
approval revisions, ordered/disjoint/conflicting changes and channel paths. `configuration-filesystem-test`
exercises two independent persisted state instances, optimistic prewrite checks, malformed files,
atomic file/folder replacement, symlink target changes, permissions, loss/reconnection, retained
journals and bounded recovery. The test fixtures create and remove only their own temporary paths.

`Scripts/run-configuration-runtime-test.sh <Debug-products-directory>` compiles a fresh application
against the built app module with a unique `com.tinycast.configuration-test.<uuid>` profile. It
exercises the real coordinator and runtime projection without starting global shortcuts, clipboard
capture or optional services. Add `--preview` to leave the actual Backup pane open for inspection.
It is separate from the standalone suite because it requires a completed Xcode Debug build.

A two-physical-Mac yadm round trip, provider-specific offline behavior and the required matched
before/after contribution video need review before an upstream PR. See the
[validation record](../validation/configuration/README.md) for captured evidence, measured results and limitations. No PR is implied by this local implementation.

Upstream replaced the window cycling toggle with three modes. Configuration now uses
`"windowCycle": "off"`, `"sizes"` or `"displays"`; replace an existing `windowCycleOnRepeat`
field with `"windowCycle": "sizes"` for `true`, or `"windowCycle": "off"` for `false`.
The removed field is rejected without overwriting the shared file.

### Upstream settings kept local

Interface size, emoji grid columns, Notes Markdown and formatting-bar preferences, navigation and
menu-search options, Apple Shortcuts enablement and per-action AI model overrides remain local.
They are explicitly excluded from the portable schema.
Custom window sizes and Apple Shortcuts, including their bindings and visibility, also stay local.
A window layout retains its local frontmost-window selection while that entry still exists.
