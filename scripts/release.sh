#!/bin/bash
# release.sh — publish Archipelago Dark.
#
#   bash scripts/release.sh
#
# 1. Fills in your GitHub username, commits, and pushes to a PUBLIC GitHub repo
#    (the store pages load their images from it), then tags a GitHub release.
# 2. Builds archipelago-theme-<version>.vsix.
# 3. VS Code Marketplace: opens the upload page (no token needed).
# 4. Open VSX (Cursor, Windsurf, VSCodium): publishes with your Open VSX token,
#    which you type in yourself; it is never saved.
#
# New version later: edit the theme, bump "version" in package.json, add a CHANGELOG entry,
# run this script again.
set -euo pipefail
cd "$(dirname "$0")/.."

say()  { printf '\033[36m→ %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$*"; }
ask()  { read -r -p "$(printf '\033[33m? %s [y/N] \033[0m' "$1")" a </dev/tty; [[ "$a" =~ ^[Yy] ]]; }

for tool in gh git jq npx; do command -v "$tool" >/dev/null || { echo "Missing: $tool"; exit 1; }; done
gh auth status >/dev/null 2>&1 || { echo "Log in first: gh auth login"; exit 1; }

publisher="$(jq -r .publisher package.json)"
name="$(jq -r .name package.json)"
version="$(jq -r .version package.json)"
user="$(gh api user --jq .login)"
vsix="$name-$version.vsix"

# ── 1. GitHub ─────────────────────────────────────────────────────────────
if grep -q "__GITHUB_USER__" package.json README.md; then
  sed -i '' "s/__GITHUB_USER__/$user/g" package.json README.md
  ok "Links now point to github.com/$user/$name"
fi
[ -d .git ] || git init -q -b main
git add -A
if ! git diff --cached --quiet; then git commit -q -m "release: v$version"; ok "Committed v$version"; fi

if gh repo view "$user/$name" >/dev/null 2>&1; then
  git push -q && ok "Pushed to github.com/$user/$name"
elif ask "Create the PUBLIC repo github.com/$user/$name and push?"; then
  gh repo create "$name" --public --source . --push \
    --description "Archipelago Dark: a calm VS Code theme of floating islands, inspired by JetBrains Islands" >/dev/null
  gh repo edit "$user/$name" --add-topic vscode-theme --add-topic vscode --add-topic dark-theme >/dev/null
  ok "Created github.com/$user/$name"
else
  echo "Stopped: the store pages need the public repo for their images."; exit 1
fi

# ── 2. Package ────────────────────────────────────────────────────────────
rm -f ./*.vsix
npx --yes @vscode/vsce@3 package -o "$vsix" >/dev/null
ok "Built $vsix"

if ! gh release view "v$version" >/dev/null 2>&1; then
  gh release create "v$version" "$vsix" --title "Archipelago Dark $version" \
    --notes "See [CHANGELOG.md](https://github.com/$user/$name/blob/main/CHANGELOG.md). Install from the VS Code Marketplace or Open VSX, or download the .vsix below." >/dev/null
  ok "GitHub release v$version (with the .vsix attached)"
fi

# ── 3. VS Code Marketplace ────────────────────────────────────────────────
cat <<EOF

VS Code Marketplace — upload $vsix:
  First time only: sign in with your Microsoft account, click "Create publisher",
                   ID: $publisher   Name: Aymen Hammami
  Then:           "+ New extension" → "Visual Studio Code" → choose $PWD/$vsix
  Updates:         ⋯ next to the extension → "Update" → choose the new .vsix
EOF
ask "Open the Marketplace publisher page now?" && open "https://marketplace.visualstudio.com/manage"

# ── 4. Open VSX ───────────────────────────────────────────────────────────
cat <<EOF

Open VSX — first time only:
  1. Sign in at https://open-vsx.org with GitHub
  2. Settings → link your Eclipse account (free) and sign the Publisher Agreement
  3. Settings → Access Tokens → Generate (keep it in a safe place; don't share it)
EOF
if ask "Publish to Open VSX now?"; then
  read -r -s -p "Open VSX token (hidden): " OVSX_PAT </dev/tty; echo
  npx --yes ovsx create-namespace "$publisher" -p "$OVSX_PAT" >/dev/null 2>&1 || true   # once; fine if it exists
  npx --yes ovsx publish "$vsix" -p "$OVSX_PAT"
  unset OVSX_PAT
  ok "Published to Open VSX: https://open-vsx.org/extension/$publisher/$name"
fi

cat <<EOF

Done. After the Marketplace finishes verifying (usually a few minutes):
  https://marketplace.visualstudio.com/items?itemName=$publisher.$name
EOF
