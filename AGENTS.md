# Project working preferences

- The user authorizes routine file inspection, code edits, builds, exports, and test/script execution within this project without repeated conversational confirmation, provided the action does not involve system security.
- Preserve user data. This permission does not authorize unrelated destructive actions, changes to system security, or bypassing platform-enforced approvals.
- Verify gameplay and multiplayer behavior before claiming completion. Compilation or successful export alone does not establish functional correctness.
- Report unfinished features and test limitations explicitly. Exported EXE and its adjacent PCK must be distributed together unless embedded packaging is configured.

- Once the user has explicitly authorized an operation during game development, treat that authorization as persistent for subsequent equivalent work in this project and do not ask for repeated confirmation, unless system security or a materially different irreversible action is involved.

- GitHub upload rule: never push or upload project changes by default. Before any git push or other GitHub upload, ask the user with a clear, prominent confirmation question and wait for explicit approval. Local edits, commits, builds, and exports may proceed under existing authorization.

- MCP development rule: use the project's MCP integration under addons/godot_ai when it is useful for development, testing, or debugging. The user authorizes this MCP usage for this project; do not ask for repeated approval for equivalent use.
