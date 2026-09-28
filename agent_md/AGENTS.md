# Project working preferences

- The user authorizes routine file inspection, code edits, builds, exports, and test/script execution within this project without repeated conversational confirmation, provided the action does not involve system security.
- Preserve user data. This permission does not authorize unrelated destructive actions, changes to system security, or bypassing platform-enforced approvals.
- Verify the behavior affected by the change before claiming completion. Gameplay and multiplayer verification are required only when the change can affect those areas; compilation or export alone is insufficient when runtime behavior is in scope.
- Report unfinished features and test limitations explicitly. Exported EXE and its adjacent PCK must be distributed together unless embedded packaging is configured.

- Markdown authorization rule:
  - Existing Markdown files whose basename is not `AGENTS.md` may be edited as needed without repeated user confirmation.
  - Creating or modifying any file whose basename is `AGENTS.md`, at any path in the repository, requires the user's explicit prior consent. A user request that explicitly asks for that creation or modification counts as consent for the requested scope only.
  - Before creating any other new Markdown file, ask the user how future edits to that file should be authorized and wait for an answer. Offer persistent pre-authorization, confirmation before every edit, or a user-defined limited scope; record the selected policy in `agent_md/authorization_log.md` before creating the file.
  - These Markdown-specific permissions do not override system or sandbox approvals, security restrictions, destructive-action safeguards, remote-upload rules, or large-file distribution rules.

- GitHub upload rule: NEVER execute or proactively offer a git push or other GitHub upload unless the user actively requests it in their own message ("我主动要求才推送"). When the user does request an upload, confirm scope (especially large binaries) before pushing. Local edits, commits, builds, and exports may proceed without asking.
- Bug record format rule: when recording a confirmed bug in the development log, the entry must pair the bug with its fix method at the same location — symptom, root cause, concrete fix implementation, and verification. Never record a bug without its fix (or an explicit "unfixed" note).
- Binary distribution rule: never tell users to fetch large binaries through the repository "Download ZIP" button — Git LFS files inside such archives are tiny pointer files, not real content. Distribute EXE/PCK via GitHub Release attachments or the media.githubusercontent.com direct URL (https://media.githubusercontent.com/media/<owner>/<repo>/main/<path>), and verify the downloaded byte size matches the local build exactly.
- Large-file upload rule: before any push that includes large binaries (EXE, PCK, or other LFS objects roughly >10 MB), additionally ask the user whether those files should be included. Offer the alternatives explicitly: push without the large files, or publish them through GitHub Releases instead. Wait for a separate explicit approval for the large files themselves.

- MCP development rule: use the project's MCP integration under addons/godot_ai when it is useful for development, testing, or debugging. The user authorizes this MCP usage for this project; do not ask for repeated approval for equivalent use.

- Risk-based validation rule: run the smallest sufficient validation set for the changed behavior, then expand only when a focused check fails, shared dependencies make the impact broader, or the user requests broader coverage. Always report what ran, what was skipped, and why.
  - Documentation, planning, rules, and logs: check only the changed text, links, encoding, Markdown structure, and scoped diff hygiene. Do not start Godot/Blender, run gameplay or ENet, or export an EXE.
  - Tool wrappers: run syntax checks and the affected wrapper or service path. Run ENet only when the network runner or networking behavior changed; run export/smoke only when the export or executable-launch path changed; do not run unrelated gameplay, visual, or performance suites.
  - Gameplay or simulation code: run the focused affected tests and the core gameplay suite when shared simulation behavior changed. Add multiplayer only for RPC, authority, command routing, snapshots, deterministic timing, or other network-visible state.
  - UI, presentation, visual code, and assets: run the relevant presentation/visual/import checks. Add performance only for hot-path or scale-sensitive changes, and add multiplayer only when replicated state or network presentation is affected.
  - Networking code or protocol: run focused/core checks plus the full ENet regression.
  - Export presets, packaging, executable startup, or requested binary delivery: generate a fresh Windows EXE and run the exported smoke check. A fresh EXE is not required for unrelated source or documentation changes.
  - Full regression, ENet, export, and smoke together are reserved for release milestones, broad cross-system/core-architecture changes, explicit user requests, or focused failures that indicate wider regression risk.

- Trusted tool wrapper rule: invoke Godot, Blender, project MCP services, tests, exports, and cleanup through the fixed PowerShell entry points under `tools/codex/`. For Codex execpolicy matching, use `powershell.exe -NoProfile -ExecutionPolicy Bypass -File <absolute-wrapper-path> ...`; do not replace these with broad raw PowerShell, Python, Godot, or Blender allow rules.
- Local-network rule: wrapper-managed MCP/Python services may bind only to `127.0.0.1`/`localhost`. External network access remains approval-gated.
- Process cleanup rule: before finishing any task that starts Godot, Blender, an exported game, MCP, or Python services, run `tools/codex/cleanup-project-processes.ps1 -StopTracked -StopUntracked` once; that command must re-query and fail if project processes or ports remain. Run a separate `-ReportOnly` pass only after background-service work, interrupted/failed cleanup, ambiguous process ownership, release handoff, or an explicit user request. Never stop unrelated or shared infrastructure processes; when ownership is ambiguous, report the PID and command line instead.

## Coding style
- Use four-space indentation consistently within new or reformatted GDScript blocks.
- Put spaces around assignment and comparison operators, and after commas in argument lists.
- In blocks of consecutive assignments whose left-hand names are similar in length, align the `=` signs in a column (for example `entity_id   = id` under `entity_type = kind`). Do not force alignment when one name is much longer or when it pushes other lines far enough to hurt readability.
- Split semicolon-separated statements into separate lines.
- Leave a blank line between functions and between distinct logical code blocks.
- Keep one primary operation per line and add concise comments at important control-flow boundaries.
- Do not force alignment when it makes long expressions harder to read.

- Local Git authorization rule: conversational confirmation is pre-granted for Git operations that do not intentionally change remote state, including status, log, diff, branch, switch, checkout, add, commit, merge, rebase, reset, clean, restore, stash, tag, and local-only history rewrite. Remote-changing operations (push, force-push, remote branch creation/deletion, or any upload) still require the user to actively request them. Network read operations and platform-enforced sandbox approvals remain subject to the environment approval mechanism.
