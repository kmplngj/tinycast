> Archived issue body submitted on 2026-09-08, before the fork feature was published.

### What should it do?

Offer an opt-in configuration folder containing a readable, versioned `settings.json`, with automatic saving of portable UI changes and automatic reload of valid external edits. A user could track that file with yadm/Git or choose an already synchronized folder. Tinycast would only handle local persistence/reload; the external tool would transport changes between Macs.

I saw the decision in #477 to defer sync while settings are changing frequently. This is a narrower, folder-based proposal for discussion when the settings model is ready. It still needs a stable schema and careful reconciliation, so it does not remove that maintenance concern. I am asking whether this scope is desirable for a future contribution, not proposing an immediate merge or asking to reopen server/cloud sync work.

**Proposed setup in Settings → Backup → Configuration location:**

- **This Mac — current storage**, the unchanged default: native UserDefaults and Application Support.
- **Dotfiles folder**: `~/.config/tinycast/settings.json`, honoring an available absolute `XDG_CONFIG_HOME`. Display the resolved path; use distinct stable/dev/beta presets.
- **Custom folder…**: native directory picker, chosen once on each Mac. The location and access metadata remain local.

An empty folder is initialized only after an explicit “Use This Folder.” An existing file gets a difference preview and “Use Folder Settings” / “Replace With This Mac’s Settings”; explicit replacement preserves the previous contents locally. Returning to This Mac retains the applied values and leaves the file intact. Reveal in Finder, Reload, and Current/Saving/Unavailable/Invalid/Conflict/Review status make behavior visible.

**Portable scope:** reviewed appearance/launcher preferences, favorites, hidden items, aliases, global/per-item bindings, custom commands, quicklinks, and window layout definitions using stable entity IDs, app bundle IDs and portable display roles. The sync allowlist must be independent of backup coverage. Credentials, Keychain, AI/MCP configuration, extensions/code/data, histories, notes, snippets, learning/caches, permission/consent switches, login items, bookmarks, machine search/tool paths, window positions and hardware display IDs stay local. Manually authored command text/URLs still need the user's review for secrets.

**File and safety contract:**

- Deterministic UTF-8 JSON with `schemaVersion`; no timestamps, device identifiers or internal metadata. Absent scalar fields use documented defaults; missing entities delete; absent bindings unbind. This is a complete effective document, unlike the backup importer's optional-field merge.
- Validate the whole candidate before applying. Reject unsupported versions, unknown fields/enums, malformed/partial JSON, conflict markers, invalid references and shortcut collisions without overwriting the file. Keep unavailable apps/actions in the document.
- Externally changed shell commands and their bindings require local review of the exact content revision. Loading never executes commands or grants capability consent.
- Serialize reconciliation, debounce local edits, watch file and directory replacements, re-read on launch/activation/wake and before writing, and use atomic same-filesystem replacement. A selected directory may be symlinked; reject a symlinked `settings.json` in v1 with actionable guidance.
- Three-way merge disjoint fields/entities against the accepted base; treat ordered arrays as units initially. Pause writes for incompatible edits/delete-versus-edit, keep base/local/incoming recovery, and offer Keep This Mac / Use Folder Version / external resolution and Reload.
- Missing, unwritable, incompatible or invalid files retain the last valid state and a local pending journal. A missing previously adopted file is never automatically recreated. Keep at least 20 distinct local recovery revisions outside the shared folder.

### Why does it belong in Tinycast?

A `.tinycast` backup is useful for explicit export/import, but tracking an archive with yadm does not make a pulled setting update a running app. A documented portable settings file would make repeatable setups and ordinary dotfiles workflows possible while keeping native storage the default and avoiding direct edits to the system preferences plist.

Transport is outside this proposal: no Git commands, accounts, server, native iCloud integration, background transport schedule, history/database sync, or promise of conflict-free simultaneous multi-Mac editing. Atomic replacement and prewrite checks cannot prevent every race with an uncoordinated editor, Git process or offline provider; detected divergence and bounded recovery need to be explicit.

### Local exploration and validation

I explored this in a local personal-fork working copy against current upstream `66b95b2c18756fd7f2a45c1f00a0f3c3f2202321`; no PR has been opened or source pushed for this feature. The exploration has a Debug build, 61 passing standalone harnesses, lint, schema/coverage/filesystem tests and a passing built-runtime fixture. Computer Use exercised the actual settings UI: native folder selection, adoption/exit, UI change → file, external atomic edit → visible control update, invalid-file status, executable review and conflict resolution. The implementation includes a schema reference, explicit coverage table, yadm walkthrough and local visual evidence.

This is **not** a claim that all contribution gates are met. Two physical Macs, actual wake/provider reconnection, full-session Carbon shortcut behavior, multi-monitor placement and a controlled signed memory/leak sweep remain to be validated. Debug Settings fixtures for both upstream and the exploration exceeded the 100 MB ceiling in sampled RSS and reported allocations in `leaks`; these are not zero-leak results or a controlled regression attribution.

Would this opt-in local-folder scope be worth revisiting once the settings model stabilizes, and are there parts of the portable scope or contract you would want reduced before an upstream contribution?
