#!/usr/bin/env bash
# release.sh — bump nosleep to a new version end-to-end.
#
# Usage:
#   ./release.sh 1.1.0
#
# What this does (in order):
#   1. Validate semver, clean tree
#   2. Update NOSLEEP_VERSION in nosleep.sh
#   3. Commit version bump (in tmad4000/nosleep)
#   4. Tag v<version> and push commit + tag
#   5. Create GitHub release with auto-generated notes
#   6. Compute SHA256 of the release tarball
#   7. Update Formula/nosleep.rb in the sibling homebrew-nosleep repo
#   8. Commit + push the tap update
#
# Requirements:
#   - Run from inside ~/code/nosleep (or any clean checkout of tmad4000/nosleep)
#   - Sibling repo at ../homebrew-nosleep, also clean, on main, pushable
#   - `gh` authenticated as the repo owner
#
# Failure-safe: every step is checked; on any error the script stops with a
# clear message and tells you which manual step is left.

set -euo pipefail

NOSLEEP_DIR="$(cd "$(dirname "$0")" && pwd)"
TAP_DIR="$(cd "${NOSLEEP_DIR}/../homebrew-nosleep" 2>/dev/null && pwd || true)"

red()    { printf "\033[31m%s\033[0m\n" "$*"; }
green()  { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
bold()   { printf "\033[1m%s\033[0m\n" "$*"; }

die() { red "ERROR: $*" >&2; exit 1; }

VERSION="${1:-}"
[ -n "${VERSION}" ] || die "usage: ./release.sh <version>   (e.g. ./release.sh 1.1.0)"
[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be semver (X.Y.Z), got: ${VERSION}"

bold "Releasing nosleep v${VERSION}"

# --- Preflight ---
[ -d "${NOSLEEP_DIR}/.git" ]               || die "${NOSLEEP_DIR} is not a git repo"
[ -d "${TAP_DIR}/.git" ]                   || die "tap repo not found at ${NOSLEEP_DIR}/../homebrew-nosleep — clone it as a sibling"
[ -f "${NOSLEEP_DIR}/nosleep.sh" ]         || die "nosleep.sh missing in ${NOSLEEP_DIR}"
[ -f "${TAP_DIR}/Formula/nosleep.rb" ]     || die "Formula/nosleep.rb missing in ${TAP_DIR}"

command -v gh        >/dev/null || die "gh CLI not found"
command -v shasum    >/dev/null || die "shasum not found"
command -v curl      >/dev/null || die "curl not found"

# Clean trees
cd "${NOSLEEP_DIR}"
[ -z "$(git status --porcelain)" ] || die "${NOSLEEP_DIR} has uncommitted changes — clean first"
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || die "${NOSLEEP_DIR} is not on 'main'"

cd "${TAP_DIR}"
[ -z "$(git status --porcelain)" ] || die "${TAP_DIR} has uncommitted changes — clean first"
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || die "${TAP_DIR} is not on 'main'"

# Tag must not already exist
cd "${NOSLEEP_DIR}"
if git rev-parse "v${VERSION}" >/dev/null 2>&1; then
    die "tag v${VERSION} already exists locally"
fi
if git ls-remote --tags origin "refs/tags/v${VERSION}" | grep -q "v${VERSION}"; then
    die "tag v${VERSION} already exists on remote"
fi

# --- Step 1: bump version in nosleep.sh ---
green "→ updating NOSLEEP_VERSION in nosleep.sh"
# macOS sed needs -i ''
sed -i.bak -E "s/^NOSLEEP_VERSION=\"[^\"]+\"/NOSLEEP_VERSION=\"${VERSION}\"/" nosleep.sh
rm -f nosleep.sh.bak

grep -q "NOSLEEP_VERSION=\"${VERSION}\"" nosleep.sh \
    || die "failed to update NOSLEEP_VERSION — check sed pattern"

git add nosleep.sh
git commit -q -m "chore(release): v${VERSION}"

# --- Step 2: tag + push ---
green "→ tagging v${VERSION} and pushing"
git tag -a "v${VERSION}" -m "v${VERSION}"
git push -q origin main
git push -q origin "v${VERSION}"

# --- Step 3: GitHub release ---
green "→ creating GitHub release"
gh release create "v${VERSION}" \
    --title "v${VERSION}" \
    --generate-notes >/dev/null

# --- Step 4: compute sha256 ---
green "→ computing SHA256 of release tarball"
TARBALL_URL="https://github.com/tmad4000/nosleep/archive/refs/tags/v${VERSION}.tar.gz"
SHA256="$(curl -fsSL "${TARBALL_URL}" | shasum -a 256 | awk '{print $1}')"
[ -n "${SHA256}" ] || die "failed to compute SHA256 from ${TARBALL_URL}"
yellow "  sha256: ${SHA256}"

# --- Step 5: patch the formula ---
green "→ patching ${TAP_DIR}/Formula/nosleep.rb"
cd "${TAP_DIR}"

sed -i.bak -E "s|/archive/refs/tags/v[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz|/archive/refs/tags/v${VERSION}.tar.gz|" Formula/nosleep.rb
sed -i.bak -E "s/^( *sha256 )\"[a-f0-9]{64}\"/\1\"${SHA256}\"/" Formula/nosleep.rb
sed -i.bak -E "s/^( *version )\"[^\"]+\"/\1\"${VERSION}\"/" Formula/nosleep.rb
rm -f Formula/nosleep.rb.bak

grep -q "${SHA256}" Formula/nosleep.rb || die "sha256 was not written to formula"
grep -q "v${VERSION}.tar.gz" Formula/nosleep.rb || die "url was not updated"
grep -q "version \"${VERSION}\"" Formula/nosleep.rb || die "version field was not updated"

git add Formula/nosleep.rb
git commit -q -m "chore(formula): bump to v${VERSION}"
git push -q origin main

bold ""
bold "✓ Released v${VERSION}"
echo "  • https://github.com/tmad4000/nosleep/releases/tag/v${VERSION}"
echo "  • brew users get the new version on next \`brew update && brew upgrade nosleep\`"
echo ""
yellow "Verify:"
echo "  brew update"
echo "  brew upgrade nosleep    # if already installed"
echo "  nosleep --version       # should print: nosleep ${VERSION}"
