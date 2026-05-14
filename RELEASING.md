# Releasing nosleep

The release flow is a single script: `./release.sh <version>`. Anything that goes wrong, stop and read the error — the script fails fast on every step.

## Normal release

```bash
# Prereqs: clean tree in both repos, on main, gh authenticated as the repo owner,
# sibling checkout of homebrew-nosleep at ../homebrew-nosleep.

cd ~/code/nosleep
./release.sh 1.1.0
```

That command does, end-to-end:
1. Bumps `NOSLEEP_VERSION` in `nosleep.sh`
2. Commits the bump on `tmad4000/nosleep`
3. Tags `v1.1.0` and pushes commit + tag
4. Creates a GitHub release with auto-generated notes
5. Computes the SHA256 of the release tarball
6. Patches `Formula/nosleep.rb` in `tmad4000/homebrew-nosleep` (url + version + sha256)
7. Commits + pushes the tap update

After it succeeds:

```bash
brew update
brew upgrade nosleep   # if already installed
nosleep --version      # should print the new version
```

## Manual release (if release.sh breaks)

If for some reason you can't use the script:

```bash
# In nosleep repo
vim nosleep.sh                                          # bump NOSLEEP_VERSION
git commit -am "chore(release): v1.1.0"
git tag v1.1.0
git push && git push --tags
gh release create v1.1.0 --generate-notes

# Compute SHA
curl -fsSL https://github.com/tmad4000/nosleep/archive/refs/tags/v1.1.0.tar.gz | shasum -a 256

# In homebrew-nosleep repo
vim Formula/nosleep.rb                                  # update url, version, sha256
git commit -am "chore(formula): bump to v1.1.0"
git push
```

## Things to test before each release

- `bash -n nosleep.sh` — syntax check
- `bash -n install.sh`
- `./nosleep.sh --help` — renders correctly
- `./nosleep.sh --version` — prints the new version
- If you changed install logic: run `install.sh` on a clean test machine

## Versioning

Semver:
- **PATCH** (1.0.0 → 1.0.1) — bug fixes, no flag changes
- **MINOR** (1.0.0 → 1.1.0) — new flags or behavior, backward compatible
- **MAJOR** (1.0.0 → 2.0.0) — flag removed or renamed, breaking change

Don't ship a major before there are users.

## Homebrew-core submission (future)

Once `tmad4000/nosleep` has ~75 stars and 30 forks, submit to homebrew-core:

```bash
brew create --tap homebrew/core https://github.com/tmad4000/nosleep/archive/refs/tags/v1.X.0.tar.gz
```

Then open a PR following [homebrew/homebrew-core CONTRIBUTING](https://docs.brew.sh/Adding-Software-to-Homebrew). After it lands, users can `brew install nosleep` (no `tmad4000/nosleep/` prefix). At that point, deprecate the tap with a one-line README pointing at homebrew-core.

Tracked in `bd` ticket: see `bd list` for the current id.
