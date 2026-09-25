# Project working preferences

- The user authorizes routine file inspection, code edits, builds, exports, and test/script execution within this project without repeated conversational confirmation, provided the action does not involve system security.
- Preserve user data. This permission does not authorize unrelated destructive actions, changes to system security, or bypassing platform-enforced approvals.
- Verify gameplay and multiplayer behavior before claiming completion. Compilation or successful export alone does not establish functional correctness.
- Report unfinished features and test limitations explicitly. Exported EXE and its adjacent PCK must be distributed together unless embedded packaging is configured.

- Once the user has explicitly authorized an operation during game development, treat that authorization as persistent for subsequent equivalent work in this project and do not ask for repeated confirmation, unless system security or a materially different irreversible action is involved.

- GitHub upload rule: NEVER execute or proactively offer a git push or other GitHub upload unless the user actively requests it in their own message ("我主动要求才推送"). When the user does request an upload, confirm scope (especially large binaries) before pushing. Local edits, commits, builds, and exports may proceed without asking.
- Bug record format rule: when recording a confirmed bug in the development log, the entry must pair the bug with its fix method at the same location — symptom, root cause, concrete fix implementation, and verification. Never record a bug without its fix (or an explicit "unfixed" note).
- Binary distribution rule: never tell users to fetch large binaries through the repository "Download ZIP" button — Git LFS files inside such archives are tiny pointer files, not real content. Distribute EXE/PCK via GitHub Release attachments or the media.githubusercontent.com direct URL (https://media.githubusercontent.com/media/<owner>/<repo>/main/<path>), and verify the downloaded byte size matches the local build exactly.
- Large-file upload rule: before any push that includes large binaries (EXE, PCK, or other LFS objects roughly >10 MB), additionally ask the user whether those files should be included. Offer the alternatives explicitly: push without the large files, or publish them through GitHub Releases instead. Wait for a separate explicit approval for the large files themselves.

- MCP development rule: use the project's MCP integration under addons/godot_ai when it is useful for development, testing, or debugging. The user authorizes this MCP usage for this project; do not ask for repeated approval for equivalent use.

- Build and validation rule: after every project modification, unless the user explicitly requests otherwise, generate a fresh Windows EXE and verify the game by running it. Export success alone is insufficient; use the project MCP for gameplay validation when available.

- Trusted tool wrapper rule: invoke Godot, Blender, project MCP services, and their Python runtimes through the fixed entry points under `tools/codex/`. For Codex execpolicy matching, use `powershell.exe -NoProfile -ExecutionPolicy Bypass -File <absolute-wrapper-path> ...`; do not replace this with a broad raw `powershell`, `python`, Godot, or Blender allow rule.
- Local-network rule: wrapper-managed MCP/Python services may bind only to `127.0.0.1`/`localhost`. External network access remains approval-gated.
- Process cleanup rule: before finishing any task that starts Godot, Blender, an exported game, MCP, or Python services, run `tools/codex/cleanup-project-processes.ps1 -StopTracked -StopUntracked`, then run it again with `-ReportOnly`. Do not claim completion while project-owned processes or ports remain. Do not stop unrelated or shared infrastructure processes; when ownership is ambiguous, report the PID and command line instead.

## Coding style
- Use four-space indentation consistently within new or reformatted GDScript blocks.
- Put spaces around assignment and comparison operators, and after commas in argument lists.
- In blocks of consecutive assignments whose left-hand names are similar in length, align the `=` signs in a column (for example `entity_id   = id` under `entity_type = kind`). Do not force alignment when one name is much longer or when it pushes other lines far enough to hurt readability.
- Split semicolon-separated statements into separate lines.
- Leave a blank line between functions and between distinct logical code blocks.
- Keep one primary operation per line and add concise comments at important control-flow boundaries.
- Do not force alignment when it makes long expressions harder to read.

- Local Git authorization rule: conversational confirmation is pre-granted for Git operations that do not intentionally change remote state, including status, log, diff, branch, switch, checkout, add, commit, merge, rebase, reset, clean, restore, stash, tag, and local-only history rewrite. Remote-changing operations (push, force-push, remote branch creation/deletion, or any upload) still require the user to actively request them. Network read operations and platform-enforced sandbox approvals remain subject to the environment approval mechanism.
