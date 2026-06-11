# Make Windows shellish actually work

This PR takes Windows support from "🧪 beta" toward a usable real-machine setup.
The final Windows design intentionally keeps one PATH entry point (`shellish.cmd`)
and lets the PowerShell profile call the Node CLI directly, avoiding the earlier
same-name `shellish.ps1` / `shellish.cmd` conflict.

## What changed

- **PowerShell hook** (`shell/profile.ps1`): PSReadLine Enter handler recovers
  the full input line and calls `node lib/shellish-cmd.js --from-shell ...`
  directly. The profile also defines a `shellish` PowerShell function that calls
  the same Node CLI with `@args`, so interactive PowerShell usage avoids CMD
  argument parsing. `CommandNotFoundAction` remains only as a best-effort
  fallback for hosts without PSReadLine. Console input/output encodings are set
  to UTF-8 for CJK/emoji sessions.
- **Windows entry point cleanup**: removed the same-name `bin/shellish.ps1`.
  `bin/shellish.cmd` is the only PATH fallback CLI on Windows. Its `version`
  path returns before Node/PATH probing, so it cannot hang on `where node`.
- **Agent path resolution** (`lib/agent-resolver.js`): generic resolver for
  pi / omp / claude / codex. It checks `where <agent>`, reads npm shims to find
  the underlying JS entry, probes npm global roots (APPDATA / NVM_HOME /
  FNM_DIR), then falls back to the bare command with `shell: true`.
- **safe-rm** (`lib/safe-rm.js`): PowerShell COM replaced with .NET BCL
  `Microsoft.VisualBasic.FileIO.FileSystem` + `RecycleOption.SendToRecycleBin`.
  It prefers `pwsh` when available, supports exit codes 3 (not found) and 4
  (trash error), and handles `--` argument separation.
- **Configuration / history**: `lib/config-win.js` reads UTF-8, UTF-8 BOM,
  UTF-16LE BOM, and UTF-16LE-without-BOM configs consistently. History filenames
  use SHA-256 keys to avoid cwd collisions.
- **Install / uninstall**: profile marker blocks (`# >>> shellish hook >>>`) are
  used instead of substring matching. Installer/uninstaller use fully-qualified
  `Microsoft.PowerShell.Management\Remove-Item` internally so they are not
  affected by user shell aliases or functions. Stale shellish shims are removed
  only by content marker match.
- **Prompt strategy**: prompt no longer teaches PowerShell command substitutions.
  It states the host OS, lets the agent adapt to its actual shell/tooling, and
  expresses deletion safety via explicit `shellish-trash`.
- **CI**: Windows workflow covers profile parsing/loading, PSReadLine classifier,
  PowerShell function argument preservation, hook marker install/uninstall,
  renderer regressions, and agent resolver shape. Unix workflow now runs on both
  macOS and Ubuntu.

## Issue coverage summary

Most Windows compatibility issues are addressed. The deliberately constrained
areas are documented:

- `Remove-Item` and the `rm`/`del`/`erase`/`rmdir`/`rd` aliases are wrapped by
  the profile to route through `shellish-trash` (PowerShell never consults PATH
  for these, so PATH shims alone cannot intercept them). Scripts opt out with
  the fully qualified `Microsoft.PowerShell.Management\Remove-Item`; pipeline
  binding (`Get-ChildItem | Remove-Item`) is not intercepted.
- Hosts without PSReadLine still fall back to `CommandNotFoundAction`, which
  cannot recover full multi-token input by PowerShell API design.
- The installer prints SHA256 for auditing but does not yet pin to signed release
  artifacts.
- Long-path handling remains warning-only; adding `\\?\` everywhere has higher
  compatibility risk than benefit for this release.

## Test coverage

- **macOS / Linux**: JS syntax checks, agent resolver tests, history key
  collision test, UTF-16LE config round-trip, bash entrypoint checks, and install
  script syntax on both `macos-latest` and `ubuntu-latest`.
- **Windows**: JS/PowerShell syntax checks, Windows PowerShell 5.1 profile parse,
  profile source tests, PSReadLine handler binding, special-character argument
  preservation through the PowerShell function, marker install/uninstall, renderer
  regressions, safe-rm no-op, and agent resolver shape.

## Migration notes

Users upgrading from versions that installed a `shellish.ps1` in `bin` should
remove it by reinstalling. The new Windows PATH entry is `shellish.cmd`; the
PowerShell profile defines the `shellish` function for argument-safe interactive
use.
