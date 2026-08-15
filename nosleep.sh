#!/bin/bash
# nosleep - Prevent your Mac from sleeping (even with the lid closed).
#
# Solves a real problem `caffeinate` does not: caffeinate prevents idle
# sleep, but the moment you close the lid your Mac sleeps anyway and
# your long-running task dies. nosleep flips the underlying pmset knob
# that survives clamshell.
#
# Repo:    https://github.com/tmad4000/nosleep
# License: MIT
# Network: zero. This script only invokes /usr/bin/pmset locally.

set -e

NOSLEEP_VERSION="1.2.1"

# The pid file stays in /tmp deliberately: macOS clears /tmp at boot, so a
# stale pid left by a killed timer can't survive a reboot and collide with a
# reused pid.
LOCK_FILE="/tmp/.nosleep-$(id -u).pid"

# The saved displaysleep value must NOT live in /tmp. pmset settings persist
# across reboot but /tmp does not, so a reboot used to strand displaysleep=0
# with no record of what to restore.
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/nosleep"
DISPLAY_STATE_FILE="${STATE_DIR}/displaysleep.val"

# Pull --keep-display / -kd out of the args wherever it appears, leaving the
# rest of the positional args (command, duration) untouched.
KEEP_DISPLAY=0
_ARGS=()
for _arg in "$@"; do
    case "${_arg}" in
        --keep-display|-kd)
            KEEP_DISPLAY=1
            ;;
        *)
            _ARGS+=("${_arg}")
            ;;
    esac
done
set -- "${_ARGS[@]+"${_ARGS[@]}"}"

# If a timed-mode timer is already running, kill it (without letting it
# re-enable sleep) so the new invocation restarts the duration from scratch.
# This is what makes triggering nosleep a second time (e.g. via a voice
# command or text-expansion shortcut) act as a "reset the 30 minutes" snooze
# instead of racing two independent timers against each other.
supersede_previous_timer() {
    [ -f "${LOCK_FILE}" ] || return 0
    local old_pid
    old_pid=$(cat "${LOCK_FILE}" 2>/dev/null) || return 0
    if [ -n "${old_pid}" ] && kill -0 "${old_pid}" 2>/dev/null; then
        echo "A nosleep timer is already running (pid ${old_pid}) — restarting it from scratch."
        kill -USR1 "${old_pid}" 2>/dev/null || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            kill -0 "${old_pid}" 2>/dev/null || break
            sleep 0.2
        done
    fi
}

show_help() {
    cat << 'EOF'
nosleep - Keep your Mac awake (lid open or closed)

USAGE:
    nosleep [DURATION]            # Timed mode (auto-recovers)
    nosleep on                    # Indefinite mode (until `nosleep off`)
    nosleep off                   # Re-enable sleep
    nosleep status                # Show current sleep state

    Add --keep-display (or -kd) to any of the above to also stop the
    DISPLAY from sleeping — e.g. `nosleep on --keep-display`. Without
    it, the screen still blanks/locks on its normal displaysleep timer
    even though the machine underneath stays awake.

    The installer also creates `nsl` as a short alias for `nosleep`
    (skip with `install.sh --no-shortcut`).

TIMED MODE (default):
    nosleep              # 30 minutes
    nosleep 2h           # 2 hours
    nosleep 45m          # 45 minutes
    nosleep 1h30m        # 1.5 hours
    nosleep 3600         # a bare number is still seconds

    DURATION is either a bare number of seconds or one or more
    <number><unit> pairs, where unit is s, m, or h. Spelled-out units
    work too — 30min, 2hours, 90sec.

    Timed mode is the SAFE default — sleep auto-recovers when the timer
    expires. If you previously ran `nosleep on` and forgot, running plain
    `nosleep` overrides indefinite mode and re-enables sleep after the
    duration. Use plain `nosleep` as a rescue if you're not sure whether
    you left sleep disabled.

    Running `nosleep` again while a timer is already counting down
    restarts the duration from scratch (snooze behavior) instead of
    racing two timers against each other — handy for a voice command
    or text-expansion trigger you can just repeat.

INDEFINITE MODE:
    nosleep on           # Disables sleep until you run `nosleep off`
    nosleep off          # Re-enable sleep right now

    Aliases: `--on`, `-on`, `-o`  → on
             `--off`, `-off`, `-O` → off
             `--status`, `-s`      → status

DISPLAY SLEEP:
    --keep-display, -kd   Also disable display sleep (screen stays lit,
                           won't lock from idle). Works with `on`, `off`,
                           and timed mode. `nosleep off` (with or without
                           the flag) always restores whatever displaysleep
                           value was in effect before you ran `on`.

OPTIONS:
    -h, --help           Show this help
    -v, --version        Print version
    --setup              Install passwordless sudoers rule for pmset
    --uninstall          Remove the binary, sudoers rule, re-enable sleep
    update               Fetch and install the latest release (opt-in network call)

NOTES:
    - Ctrl+C cleanly re-enables sleep (trap handler).
    - Safe to close the laptop lid while running.
    - No telemetry. The ONLY network call in this script is the opt-in
      `nosleep update` command. Every other command is local-only.

FIRST-TIME SETUP:
    Run `nosleep --setup` once. It writes a sudoers rule that allows
    pmset (and only pmset) to run without a password prompt. Anything
    else still requires your password, so this is a small, scoped grant.

EOF
}

require_macos() {
    if [ "$(uname -s)" != "Darwin" ]; then
        echo "Error: nosleep only supports macOS. On Linux use 'systemd-inhibit', on Windows use 'powercfg'." >&2
        exit 1
    fi
}

setup_sudoers() {
    local user="${USER:-$(whoami)}"
    local rule="${user} ALL=(ALL) NOPASSWD: /usr/bin/pmset"
    echo "Installing passwordless sudoers rule for pmset..."
    echo "  Rule: ${rule}"
    echo "  File: /etc/sudoers.d/pmset"
    echo "(You will be prompted for your password once, to write the file.)"
    echo "${rule}" | sudo tee /etc/sudoers.d/pmset > /dev/null
    sudo chmod 0440 /etc/sudoers.d/pmset
    echo "Done. You can now run 'nosleep' without a password prompt."
}

update_self() {
    echo "Updating nosleep to the latest release..."
    echo "(Fetching the installer from github.com/tmad4000/nosleep)"
    if ! command -v curl >/dev/null 2>&1; then
        echo "Error: curl is required to update." >&2
        exit 1
    fi
    curl -fsSL "https://raw.githubusercontent.com/tmad4000/nosleep/main/install.sh" | bash
}

uninstall_self() {
    echo "Re-enabling sleep (in case it was disabled)..."
    sudo pmset -a disablesleep 0 2>/dev/null || true
    restore_display 2>/dev/null || true

    local bin="/usr/local/bin/nosleep"
    local shortcut="/usr/local/bin/nsl"

    if [ -L "${shortcut}" ] && [ "$(readlink "${shortcut}")" = "${bin}" ]; then
        echo "Removing ${shortcut} shortcut..."
        sudo rm -f "${shortcut}"
    fi

    if [ -f "${bin}" ]; then
        echo "Removing ${bin}..."
        sudo rm -f "${bin}"
    fi

    if [ -f /etc/sudoers.d/pmset ]; then
        echo "Removing /etc/sudoers.d/pmset..."
        sudo rm -f /etc/sudoers.d/pmset
    fi

    echo "nosleep uninstalled. Sleep is re-enabled."
}

show_status() {
    echo "Current sleep settings:"
    pmset -g | grep -E "(SleepDisabled|sleep|disablesleep|displaysleep)" || true
    echo ""
    if is_sleep_disabled; then
        echo "Sleep is currently DISABLED (Mac will stay awake, including with lid closed)."
    else
        echo "Sleep is currently ENABLED (default behavior)."
    fi
    # Report from live pmset, not from whether our state file happens to exist —
    # the file can be absent while the setting is still applied.
    if [ "$(get_displaysleep)" = "0" ]; then
        echo "Display sleep is currently DISABLED too (screen stays on, won't lock from idle)."
        if [ -f "${DISPLAY_STATE_FILE}" ]; then
            echo "  'nosleep off' will restore displaysleep to $(cat "${DISPLAY_STATE_FILE}")."
        else
            echo "  No saved value — 'nosleep off' will restore the macOS default (10)."
        fi
    fi
}

is_sleep_disabled() {
    # Returns 0 (true) if disablesleep is currently 1. No sudo needed for read.
    pmset -g 2>/dev/null | grep -E "SleepDisabled[[:space:]]+1" >/dev/null 2>&1
}

get_displaysleep() {
    pmset -g 2>/dev/null | awk '/^ *displaysleep/{print $2; exit}'
}

# Idempotent: only remembers the pre-existing displaysleep value the first
# time it's called, so repeated `on --keep-display` invocations (or a timed
# mode that supersedes an `on`) don't clobber the real value with 0.
keep_display_on() {
    if [ ! -f "${DISPLAY_STATE_FILE}" ]; then
        local prev
        prev=$(get_displaysleep)
        # Never record 0 as the "previous" value. A 0 here is almost certainly
        # our own leftover from an earlier run, and saving it would bake
        # displaysleep=0 in permanently. Fall back to the macOS stock value.
        if [ -z "${prev}" ] || [ "${prev}" = "0" ]; then
            prev=10
        fi
        mkdir -p "${STATE_DIR}"
        echo "${prev}" > "${DISPLAY_STATE_FILE}"
    fi
    sudo pmset -a displaysleep 0
    echo "Display sleep disabled too — screen will stay on and won't lock from idle."
}

restore_display() {
    local prev
    if [ -f "${DISPLAY_STATE_FILE}" ]; then
        prev=$(cat "${DISPLAY_STATE_FILE}" 2>/dev/null)
    elif [ "$(get_displaysleep)" = "0" ]; then
        # No saved value, but the display is still pinned on — most likely a
        # pre-1.2.1 run whose state lived in /tmp and was cleared at boot. The
        # original value is unrecoverable, so fall back to the macOS default
        # rather than silently leaving the display unable to sleep.
        prev=10
        echo "No saved displaysleep value found — restoring the macOS default (${prev})."
    else
        return 0
    fi
    [ -n "${prev}" ] || return 0
    # Restore first, delete second: under 'set -e' a failing sudo would
    # otherwise lose the saved value permanently.
    sudo pmset -a displaysleep "${prev}"
    rm -f "${DISPLAY_STATE_FILE}"
}

require_macos

case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -v|--version)
        echo "nosleep ${NOSLEEP_VERSION}"
        exit 0
        ;;
    -s|--status|status)
        show_status
        exit 0
        ;;
    --setup)
        setup_sudoers
        exit 0
        ;;
    --uninstall)
        uninstall_self
        exit 0
        ;;
    update|--update)
        update_self
        exit 0
        ;;
    on|--on|-on|-o)
        echo "Disabling sleep indefinitely..."
        # Cancel any countdown still running, or it would later fire and
        # re-enable sleep out from under indefinite mode.
        supersede_previous_timer
        rm -f "${LOCK_FILE}" 2>/dev/null || true
        sudo pmset -a disablesleep 1
        if [ "${KEEP_DISPLAY}" -eq 1 ]; then
            keep_display_on
        fi
        echo "Sleep disabled. Options to re-enable:"
        echo "  • 'nosleep off'        — re-enable right now"
        echo "  • 'nosleep'            — auto-recover in 30 minutes (rescue mode)"
        echo "  • 'nosleep 2h'         — auto-recover after a specific duration"
        echo "                           (also 45m, 1h30m, or bare seconds like 3600)"
        exit 0
        ;;
    off|--off|-off|-O)
        echo "Re-enabling sleep..."
        supersede_previous_timer
        rm -f "${LOCK_FILE}" 2>/dev/null || true
        sudo pmset -a disablesleep 0
        restore_display
        echo "Sleep re-enabled."
        exit 0
        ;;
esac

# Accepts bare seconds (1800, the original contract) or unit-suffixed
# durations (90s, 45m, 2h, 1h30m, "30 min"). Echoes the total in seconds;
# returns non-zero without output if the input isn't a duration at all.
#
# Alternatives are ordered longest-first on purpose: with `s` before
# `seconds`, "30seconds" would match `s` and silently mean 30 SECONDS
# instead of erroring or parsing as intended.
NOSLEEP_UNIT_RE='(seconds|second|secs|sec|s|minutes|minute|mins|min|m|hours|hour|hrs|hr|h)'

parse_duration() {
    local input
    # Lowercase via tr, not ${x,,} — macOS ships bash 3.2.
    input=$(printf '%s' "$1" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    if [[ "${input}" =~ ^[0-9]+$ ]]; then
        echo "${input}"
        return 0
    fi
    # One or more <number><unit> pairs and nothing else.
    if [[ ! "${input}" =~ ^([0-9]+${NOSLEEP_UNIT_RE})+$ ]]; then
        return 1
    fi
    local total=0 rest="${input}" num unit
    while [[ "${rest}" =~ ^([0-9]+)${NOSLEEP_UNIT_RE}(.*)$ ]]; do
        num="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[2]}"
        rest="${BASH_REMATCH[3]}"
        case "${unit}" in
            s*) total=$((total + num)) ;;
            m*) total=$((total + num * 60)) ;;
            h*) total=$((total + num * 3600)) ;;
        esac
    done
    echo "${total}"
}

# Join the remaining args so `nosleep 30 min` parses as one duration instead
# of silently taking "30" as seconds and dropping "min" on the floor.
DURATION_INPUT="$*"
[ -n "${DURATION_INPUT}" ] || DURATION_INPUT=1800

if ! DURATION=$(parse_duration "${DURATION_INPUT}"); then
    echo "Error: unknown command or invalid duration: ${DURATION_INPUT}" >&2
    echo "Durations are bare seconds (1800) or units (90s, 45m, 2h, 1h30m)." >&2
    echo "Run 'nosleep --help' for usage." >&2
    exit 1
fi

MINUTES=$((DURATION / 60))
HOURS=$((MINUTES / 60))

format_duration() {
    if [ ${HOURS} -gt 0 ]; then
        printf "%dh %dm" "${HOURS}" "$((MINUTES % 60))"
    elif [ ${MINUTES} -gt 0 ]; then
        printf "%d minutes" "${MINUTES}"
    else
        printf "%d seconds" "${DURATION}"
    fi
}

# Timed mode is the command people run blind (voice trigger, text expansion,
# muscle memory), so it prints its own escape hatches the way `on` does —
# otherwise nothing on screen ever mentions --help or the other durations.
print_timed_hint() {
    echo "  • other durations: 'nosleep 2h', 'nosleep 45m', 'nosleep 1h30m'"
    echo "  • stop early:      Ctrl+C, or 'nosleep off' from another shell"
    echo "  • indefinite:      'nosleep on'   ·   all options: 'nosleep --help'"
}

supersede_previous_timer

if is_sleep_disabled; then
    echo "⚠  Sleep is already disabled (probably from 'nosleep on')."
    echo "   Overriding to timed mode — re-enabling sleep in $(format_duration)."
else
    echo "Disabling sleep for $(format_duration)..."
fi
print_timed_hint

sudo pmset -a disablesleep 1
if [ "${KEEP_DISPLAY}" -eq 1 ]; then
    keep_display_on
fi
echo $$ > "${LOCK_FILE}"

cleanup() {
    echo ""
    echo "Re-enabling sleep..."
    sudo pmset -a disablesleep 0
    restore_display
    rm -f "${LOCK_FILE}" 2>/dev/null || true
    exit 0
}
# HUP matters as much as INT/TERM: closing the terminal window sends SIGHUP,
# and without it here the countdown died leaving sleep disabled forever.
trap cleanup INT TERM HUP

# A newer nosleep invocation superseded us — hand off silently. It has
# already (or is about to) written its own PID to the lock file, so don't
# touch it and don't re-enable sleep (or displaysleep) out from under it.
trap 'exit 0' USR1

sleep "${DURATION}"

echo "Time's up. Re-enabling sleep..."
sudo pmset -a disablesleep 0
restore_display
rm -f "${LOCK_FILE}" 2>/dev/null || true
