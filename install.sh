#!/bin/bash
# nosleep installer
#
# Run via:
#   curl -fsSL https://raw.githubusercontent.com/tmad4000/nosleep/main/install.sh | bash
#
# What this does:
#   1. Downloads nosleep.sh to /usr/local/bin/nosleep
#   2. Makes it executable
#   3. Optionally writes /etc/sudoers.d/pmset (passwordless pmset)
#
# Every step is reversible: `nosleep --uninstall` undoes everything.

set -e

NOSLEEP_REPO="${NOSLEEP_REPO:-tmad4000/nosleep}"
NOSLEEP_BRANCH="${NOSLEEP_BRANCH:-main}"
NOSLEEP_URL="https://raw.githubusercontent.com/${NOSLEEP_REPO}/${NOSLEEP_BRANCH}/nosleep.sh"
INSTALL_PATH="/usr/local/bin/nosleep"

bold=$(tput bold 2>/dev/null || true)
green=$(tput setaf 2 2>/dev/null || true)
yellow=$(tput setaf 3 2>/dev/null || true)
reset=$(tput sgr0 2>/dev/null || true)

say() { echo "${bold}${1}${reset}"; }
ok()  { echo "${green}✓${reset} ${1}"; }
warn(){ echo "${yellow}!${reset} ${1}"; }

if [ "$(uname -s)" != "Darwin" ]; then
    echo "Error: nosleep only supports macOS." >&2
    echo "  Linux equivalent:   systemd-inhibit --what=sleep" >&2
    echo "  Windows equivalent: powercfg /requestsoverride" >&2
    exit 1
fi

say "Installing nosleep from ${NOSLEEP_REPO}@${NOSLEEP_BRANCH}..."

if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl is required. Install Xcode Command Line Tools and retry." >&2
    exit 1
fi

TMP="$(mktemp -t nosleep.XXXXXX)"
trap 'rm -f "${TMP}"' EXIT

curl -fsSL "${NOSLEEP_URL}" -o "${TMP}"

if ! head -n 1 "${TMP}" | grep -q '^#!/bin/bash'; then
    echo "Error: downloaded file does not look like the nosleep script." >&2
    echo "URL: ${NOSLEEP_URL}" >&2
    exit 1
fi

if [ -w "$(dirname "${INSTALL_PATH}")" ]; then
    mv "${TMP}" "${INSTALL_PATH}"
    chmod +x "${INSTALL_PATH}"
else
    echo "Installing to ${INSTALL_PATH} (requires sudo for /usr/local/bin)..."
    sudo mv "${TMP}" "${INSTALL_PATH}"
    sudo chmod +x "${INSTALL_PATH}"
fi
ok "Installed ${INSTALL_PATH}"

if [ -f /etc/sudoers.d/pmset ]; then
    ok "Passwordless pmset already configured (/etc/sudoers.d/pmset exists)"
else
    say ""
    say "Next: run 'nosleep --setup' to grant passwordless pmset."
    warn "Without this you'll be prompted for your password every time."
    warn "Setup writes ONE sudoers line allowing only /usr/bin/pmset — nothing else."
fi

say ""
say "Try it:"
echo "  nosleep --status   # show current sleep state"
echo "  nosleep --on       # disable sleep until --off"
echo "  nosleep --off      # re-enable sleep"
echo "  nosleep 3600       # disable for 1 hour, auto-recover"
echo ""
echo "Uninstall any time: nosleep --uninstall"
