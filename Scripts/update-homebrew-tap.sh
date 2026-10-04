#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

TAG="${1:?usage: update-homebrew-tap.sh <tag> <dmg>}"
DMG="${2:?usage: update-homebrew-tap.sh <tag> <dmg>}"
TAP_REPO="${TAP_REPO:-guilhermehrcosta/homebrew-tap}"

VERSION="${TAG#v}"
TAG_PREFIX="${TAG%"$VERSION"}"
SHA256="$(shasum -a 256 "$DMG" | cut -d ' ' -f 1)"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

if [[ -n "${TAP_DEPLOY_KEY:-}" ]]; then
    printf '%s\n' "$TAP_DEPLOY_KEY" > "$WORKDIR/deploy_key"
    chmod 600 "$WORKDIR/deploy_key"
    export GIT_SSH_COMMAND="ssh -i $WORKDIR/deploy_key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
    TAP_URL="${TAP_URL:-git@github.com:$TAP_REPO.git}"
else
    TAP_URL="${TAP_URL:-https://github.com/$TAP_REPO.git}"
fi

git clone --quiet --depth 1 "$TAP_URL" "$WORKDIR/tap"
mkdir -p "$WORKDIR/tap/Casks"
sed -e "s|@VERSION@|$VERSION|" -e "s|@SHA256@|$SHA256|" -e "s|@TAG_PREFIX@|$TAG_PREFIX|" \
    Packaging/space-disk-free.rb > "$WORKDIR/tap/Casks/space-disk-free.rb"

cd "$WORKDIR/tap"
git add Casks/space-disk-free.rb
if git diff --cached --quiet; then
    echo "✓ cask already at $VERSION"
    exit 0
fi
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    git config user.name "github-actions[bot]"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
fi
git commit --quiet -m "Update space-disk-free to $VERSION"
git push --quiet origin HEAD
echo "✓ $TAP_REPO: space-disk-free $VERSION ($SHA256)"
