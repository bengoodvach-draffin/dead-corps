# tools/

Local developer tooling for Dead Corps. Nothing here ships in the game or an
export — it's a manual safety net you run before committing.

## `check.ps1` — parse-error gate + advisory lint

The automated safety net the project previously lacked. Run it before committing,
especially after bulk-editing or commenting out code (the partial-comment
parse-error trap CLAUDE.md warns about).

```powershell
powershell -ExecutionPolicy Bypass -File tools/check.ps1   # Windows PowerShell 5.1
pwsh tools/check.ps1                                        # PowerShell 7+
```

What it does:

1. **Parse-error gate (hard fail — exit 1).** Runs headless
   `godot --check-only` over every `scripts/**/*.gd` and fails on any GDScript
   `Parse Error`. This catches the "empty block after a partially-commented
   `print()`" syntax error — which **gdlint does not catch**.
2. **Semantic notes (advisory).** Non-autoload compile errors, with the known
   benign `WorldBounds` autoload false-positive filtered out.
3. **gdlint (advisory).** Style findings using `../gdlintrc`. Never fails the
   gate — informational only.

Exit codes: `0` clean · `1` parse error found · `2` Godot binary not located.

### Godot binary

Resolution order: `-Godot <path>` arg → `GODOT_BIN` env var → the hardcoded
default (`...\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe`).
Use the **`_console.exe`** build so CLI output is captured. If you move Godot:

```powershell
$env:GODOT_BIN = "D:\path\to\Godot_v4.6-stable_win64_console.exe"
pwsh tools/check.ps1
```

### Why per-file `--check-only` and not `--import`

A full `--import` does **not** report parse errors in scene-attached scripts
(verified — it scans/imports but doesn't surface them). Per-file `--check-only`
does, reliably. Its only quirk: a single-script check doesn't register the
`WorldBounds` autoload, so it emits a benign `Identifier not found: WorldBounds`
compile error. Real *syntax* errors are reported as `Parse Error:` **before**
identifier resolution, so the gate keys on that string and is immune to the
false-positive.

## gdtoolkit (gdlint / gdformat)

```
pip install gdtoolkit      # provides gdlint and gdformat
```

Linter config is `../gdlintrc` (repo root). Pure-noise rules (trailing
whitespace, member ordering, line length, file/method size) are disabled there so
the output is actionable — real signal only (unused args, mixed tabs/spaces,
naming, self-comparison). The remaining ~16 advisory findings are pre-existing and
intentionally left for a future cleanup pass.

### gdformat — opt-in only, NOT part of the gate

`gdformat` auto-reformats code. On this codebase it would rewrite ~440 whitespace
spots and reflow long lines = a massive diff across every file. **Do not run it
casually.** If you ever want it, preview first and commit it as its own isolated
formatting commit:

```powershell
gdformat --diff scripts            # preview only, changes nothing
gdformat scripts                   # apply (separate commit, review the diff)
```
