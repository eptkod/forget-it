#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

repo_url="${1:-}"
if [[ ! "$repo_url" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(\.git)?$ ]]; then
    echo "Usage: bash scripts/publish-source.sh https://github.com/USERNAME/forget-it.git" >&2
    exit 2
fi
if [[ "$repo_url" == *"YOUR-USERNAME"* || "$repo_url" == *"USERNAME"* ]]; then
    echo "Replace YOUR-USERNAME with your actual GitHub username or paste the HTTPS URL from the green Code button." >&2
    exit 2
fi

if [[ ! -d .git ]]; then
    git init -b main
fi

existing_remote="$(git remote get-url origin 2>/dev/null || true)"
if [[ -n "$existing_remote" && "$existing_remote" != "$repo_url" ]]; then
    echo "This folder already has a different origin: $existing_remote" >&2
    exit 1
fi

git add --all
if ! git diff --cached --quiet; then
    echo "Files in the next public commit:"
    GIT_PAGER=cat git -c core.quotePath=false diff --cached --name-only
    echo
    echo "Public commit author: $(git config user.name || echo 'not set') <$(git config user.email || echo 'not set')>"
    read -r -p "Publish this source and author identity to $repo_url? [y/N] " answer
    [[ "$answer" == "y" || "$answer" == "Y" ]] || exit 0
    git commit -m "Add forget it macOS app"
else
    echo "No new source changes to commit."
fi

if [[ -z "$existing_remote" ]]; then
    git remote add origin "$repo_url"
fi

git push -u origin main
echo "Source published: ${repo_url%.git}"
echo "Upload dist/forget-it.dmg separately as a GitHub Release asset."
