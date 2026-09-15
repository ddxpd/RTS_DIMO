# Task Plan

## Goal
Correct the current Godot prototype's identified structural/runtime issues and produce an executable build.

## Phases
- [in_progress] 7. Fix Guest ownership and command scheduling; verify with two network processes
- [pending] 8. Re-export the Guest fix
- [complete] 1. Inspect current project and define concrete fixes
- [complete] 2. Refactor scene structure and runtime code
- [complete] 3. Validate with Godot MCP/editor
- [complete] 4. Export executable and verify artifact
- [complete] 5. Add non-pausing Esc menu, key help, and operation hints
- [complete] 6. Re-validate and re-export updated executable

## Errors Encountered
| Error | Attempt | Resolution |
|---|---:|---|
| session-catchup.py not found under .codebuddy path | 1 | Continued with current workspace state; no prior planning files found |
| Parser Error: Cannot infer type of `pos` at `scripts/main.gd:125` | 1 | Added explicit `Vector2` type annotation |
| Multiple truncated/unterminated status strings in `scripts/main.gd` | 1 | Replaced script with typed, parseable runtime implementation |
| Windows export templates missing from Godot user directory | 1 | Downloaded official 4.7.2 template archive and installed the Windows x86_64 templates |
| Project-local template archive was truncated and lacked Windows entries | 1 | Used the complete official archive from the Godot release endpoint |
| MCP input helper rejected `ESC` key name | 1 | Used the accepted `Escape` key name for verification |

## Decisions
- Preserve the existing prototype's network behavior while fixing startup/runtime blockers.
- Use the connected Godot MCP/editor for validation and export where possible.
- Export with the existing `Windows Desktop` preset and preserve the non-embedded PCK output.
- Keep the Esc menu in the same runtime-created UI and never set `SceneTree.paused`.
