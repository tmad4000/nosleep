# nosleep

> Keep your Mac running with the lid closed — without walking through an airport holding it half open.

[![Shell](https://img.shields.io/badge/shell-bash-89e051)](#)
[![Platform](https://img.shields.io/badge/platform-macOS-blue)](#)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Network](https://img.shields.io/badge/network-zero-brightgreen)](#privacy--what-this-script-actually-does)

```bash
nosleep --on   # disable sleep until you say otherwise
nosleep --off  # re-enable
nosleep 3600   # disable for 1 hour, auto-re-enable
```

That's it. ~150 lines of bash, zero dependencies, zero network calls.

---

## Why this exists

On **May 13, 2026**, Business Insider ran a story called *"Good news, AI coders: You can keep your laptop running while closed"* about developers walking around with their MacBook lids cracked open so their AI agents wouldn't die mid-task. One quoted developer:

> "didn't know" about the tricks. "I think it's too much friction."

The friction is real — Apple's built-in `caffeinate` only prevents **idle** sleep. The moment you close the lid, your Mac sleeps anyway and your long-running coding agent, training job, download, or background task dies.

There's exactly one knob that actually works: `sudo pmset -a disablesleep 1`. But it prompts for a password every time, so nobody uses it. `nosleep` is that knob, wrapped to need a password exactly once (during setup), with a clean Ctrl+C trap so it can't leave your machine awake forever.

That's the whole product.

---

## Install

### Option 1: Homebrew (recommended)

```bash
brew install tmad4000/nosleep/nosleep
nosleep --setup   # one-time: grant passwordless pmset (prompts for password once)
```

### Option 2: Curl

```bash
curl -fsSL https://raw.githubusercontent.com/tmad4000/nosleep/main/install.sh | bash
```

The installer drops the script at `/usr/local/bin/nosleep`, then runs `nosleep --setup` for you. Both steps are reversible (see [Uninstall](#uninstall) below).

### Option 3: Manual

```bash
curl -o /usr/local/bin/nosleep https://raw.githubusercontent.com/tmad4000/nosleep/main/nosleep.sh
chmod +x /usr/local/bin/nosleep
nosleep --setup
```

---

## Usage

```bash
nosleep              # 30 minutes (default), auto-re-enable
nosleep 3600         # 1 hour
nosleep 28800        # 8 hours (overnight job)
nosleep --on         # indefinitely, until you run --off
nosleep --off        # re-enable sleep right now
nosleep --status     # show current sleep state
nosleep --help       # full help
nosleep --version
```

**Workflow for a long agent session:**

```bash
nosleep --on
# ...close the lid, walk to the coffee shop, your agent keeps running...
nosleep --off       # when you're done
```

**Workflow for a finite task:**

```bash
nosleep 7200        # 2 hours
# Ctrl+C any time to cleanly re-enable sleep
```

---

## How it works

`nosleep` is a 150-line bash wrapper around one Apple-supported command:

```bash
sudo pmset -a disablesleep 1   # disable sleep
sudo pmset -a disablesleep 0   # re-enable sleep
```

The `--setup` step writes a single sudoers rule at `/etc/sudoers.d/pmset`:

```
your_username ALL=(ALL) NOPASSWD: /usr/bin/pmset
```

That grants passwordless access to **only** `pmset` — not "all sudo," just the power-management binary Apple already ships. Everything else still needs your password.

The timed mode (`nosleep 3600`) installs a `trap` on `INT` and `TERM`, so closing the terminal or Ctrl+C cleanly re-enables sleep. The script will never leave your Mac unable to sleep on its own.

---

## Privacy — what this script actually does

**Zero network access.** This script only invokes `/usr/bin/pmset` on your local machine. There is no telemetry, no analytics, no update check, no phone-home. Read [the source](nosleep.sh) — it's 150 lines.

Search the script for `curl`, `wget`, or any network call. There aren't any.

---

## Uninstall

```bash
nosleep --uninstall
```

Removes the binary at `/usr/local/bin/nosleep`, removes `/etc/sudoers.d/pmset`, and re-enables sleep. Or, if you installed via Homebrew:

```bash
brew uninstall nosleep
sudo rm /etc/sudoers.d/pmset    # if you ran --setup
```

---

## FAQ

**Q: Won't this drain my battery if I forget to turn it off?**
A: Yes — that's why timed mode exists. `nosleep 3600` auto-re-enables after an hour. The `--on` / `--off` mode is for sessions you actively manage.

**Q: Is this safe to run with the lid closed?**
A: Yes, that's the entire point. The Mac will continue running on battery (or AC if plugged in) until you call `--off` or the timer expires.

**Q: Does this work on Apple Silicon?**
A: Yes, M1/M2/M3/M4 all use the same `pmset` interface.

**Q: Why not just use [Amphetamine](https://apps.apple.com/us/app/amphetamine/id937984704)?**
A: Amphetamine is great if you want a GUI. `nosleep` is for people who live in the terminal — one command, scriptable, no app to install, no menu bar icon. Use whichever fits.

**Q: Does this prevent the screen from turning off too?**
A: `disablesleep` affects system sleep, not display sleep. Combine with `caffeinate -d` if you also want the display to stay on.

**Q: What about clamshell mode with an external monitor?**
A: That already works on macOS by default when connected to power + external display + keyboard. `nosleep` is for the *no-external-monitor* case — i.e. you actually want your closed laptop to keep computing.

---

## Not on macOS?

| OS | Equivalent |
|---|---|
| **Linux (systemd)** | `systemd-inhibit --what=sleep --who=me --why="long task" sleep 3600` |
| **Linux (any)** | Disable suspend in your DE settings, or `xset s off; xset -dpms` |
| **Windows** | `powercfg /requestsoverride PROCESS yourapp.exe SYSTEM` or use [Don't Sleep](https://www.softwareok.com/?seite=Microsoft/DontSleep) |

This repo is macOS-only by design. The pattern is the same everywhere: find your OS's "disable suspend" knob, wrap it in something that auto-cleans up.

---

## Contributing

Issues and PRs welcome. Keep it small. The whole appeal of this tool is that you can read every line in 30 seconds.

If you ship a port for another OS, link it here and I'll add a row to the table.

---

## Credits

Originally part of [vibe-coding-guide](https://github.com/tmad4000/vibe-coding-guide), spun out as a standalone repo after the [May 13, 2026 Business Insider story](https://www.aol.com/articles/good-news-ai-coders-keep-091502000.html) made it clear a lot of people needed this.

Built by [@tmad4000](https://github.com/tmad4000). MIT licensed.
