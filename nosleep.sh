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

NOSLEEP_VERSION="1.0.0"

show_help() {
    cat << 'EOF'
nosleep - Keep your Mac awake (lid open or closed)

USAGE:
    nosleep [OPTIONS] [DURATION_SECONDS]

DURATION:
    Time in seconds to keep awake. Default: 1800 (30 minutes).
        nosleep              # 30 minutes
        nosleep 3600         # 1 hour
        nosleep 28800        # 8 hours

OPTIONS:
    -h, --help        Show this help
    -v, --version     Print version
    -s, --status      Show current sleep settings
    --on              Disable sleep indefinitely (until --off)
    --off             Re-enable sleep
    --setup           Install passwordless sudoers rule for pmset
    --uninstall       Remove the binary, sudoers rule, re-enable sleep

NOTES:
    - Ctrl+C cleanly re-enables sleep (trap handler).
    - Timed runs auto-re-enable sleep when the duration elapses.
    - Safe to close the laptop lid while running.
    - Network access: NONE. This script only calls pmset.

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

uninstall_self() {
    echo "Re-enabling sleep (in case it was disabled)..."
    sudo pmset -a disablesleep 0 2>/dev/null || true

    local bin="/usr/local/bin/nosleep"
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
    sudo pmset -g | grep -E "(SleepDisabled|sleep|disablesleep)" || true
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
    -s|--status)
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
    --on|-on)
        echo "Disabling sleep indefinitely..."
        sudo pmset -a disablesleep 1
        echo "Sleep disabled. Run 'nosleep --off' to re-enable."
        exit 0
        ;;
    --off|-off)
        echo "Re-enabling sleep..."
        sudo pmset -a disablesleep 0
        echo "Sleep re-enabled."
        exit 0
        ;;
esac

DURATION=${1:-1800}

if ! [[ "${DURATION}" =~ ^[0-9]+$ ]]; then
    echo "Error: Duration must be a positive integer (seconds)." >&2
    echo "Run 'nosleep --help' for usage." >&2
    exit 1
fi

MINUTES=$((DURATION / 60))
HOURS=$((MINUTES / 60))

if [ ${HOURS} -gt 0 ]; then
    echo "Disabling sleep for ${HOURS}h $((MINUTES % 60))m..."
else
    echo "Disabling sleep for ${MINUTES} minutes..."
fi

sudo pmset -a disablesleep 1

cleanup() {
    echo ""
    echo "Re-enabling sleep..."
    sudo pmset -a disablesleep 0
    exit 0
}
trap cleanup INT TERM

sleep "${DURATION}"

echo "Time's up. Re-enabling sleep..."
sudo pmset -a disablesleep 0
