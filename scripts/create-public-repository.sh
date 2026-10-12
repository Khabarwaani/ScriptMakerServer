#!/bin/sh
# Run from this repository after `gh auth login`.
set -eu
cd "$(dirname "$0")/.."
repository_name="${1:-Khabarwaani/ScriptMakerServer}"
gh auth status
if [ ! -d .git ]; then
    git init -b main
fi
git add .
if ! git diff --cached --quiet; then
    git commit -m "feat: scaffold Swift agent server and Xcode workspace"
fi
if git remote get-url origin >/dev/null 2>&1; then
    echo "An origin remote already exists; no new repository was created."
    exit 1
fi
gh repo create "$repository_name" --public --source=. --remote=origin --push
