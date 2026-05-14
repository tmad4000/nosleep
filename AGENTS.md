# AGENTS.md — guidance for AI agents working on nosleep

This is a tiny utility repo. The whole appeal is that you can read every line in 30 seconds. Keep it that way.

## Hard rules

- **Stay under 250 lines of bash total.** Anything longer needs justification.
- **Zero network calls.** No curl, wget, http fetches at runtime. The script only invokes `/usr/bin/pmset`.
- **Zero non-shell dependencies.** No Python, Node, Ruby. Pure bash + macOS-shipped binaries (`pmset`, `sudo`, `sed`, etc.).
- **macOS only.** Don't add Linux/Windows code paths — those OSes have native solutions (`systemd-inhibit`, `powercfg`). Link them in the README, don't reimplement them.
- **Reversibility is the contract.** Every action must be undoable. `--uninstall` must restore the system to pre-install state (binary removed, sudoers rule removed, sleep re-enabled).
- **`bash -n` must pass.** Run it before committing any change to `*.sh`.

## What to test before declaring a change done

1. `bash -n nosleep.sh` — syntax
2. `bash -n install.sh` — syntax
3. `./nosleep.sh --help` — renders
4. `./nosleep.sh --version` — prints version
5. `./nosleep.sh --status` — invokes pmset successfully
6. If you touched install logic: dry-run the install on a throwaway path

Note: you can't actually test `--on` / `--off` / timed mode in CI because they require `sudo`. Manual smoke is required for changes to those code paths.

## Releasing

See `RELEASING.md`. TL;DR:

```bash
./release.sh 1.X.Y
```

This handles the full tag → release → SHA256 → tap update dance.

## What NOT to change without discussion

- The CLI surface — flag names, default duration (1800s), exit codes. People script against this.
- The sudoers file path (`/etc/sudoers.d/pmset`) — `--uninstall` must keep finding it.
- The install path (`/usr/local/bin/nosleep`). If you change it, update `--uninstall` AND the brew formula AND the curl installer in lockstep.

## Issue tracking

This repo uses [`bd`](https://github.com/anthropic-experimental/beads). Run `bd list` to see open work, `bd ready` for unblocked tasks.

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
