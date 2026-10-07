#!/usr/bin/env bash
# Reproduces every command in this README inside a throwaway repo.
# Usage: ./demo.sh   (prints each command, then its output)
set -e
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }

SANDBOX=$(mktemp -d)/git-demo
mkdir -p "$SANDBOX" && cd "$SANDBOX"
git init -q -b main
git config user.name "Milap Kothari"
git config user.email "milapkothari27@gmail.com"

echo "### Task 1: git commit -m vs git commit -a -m"
run 'echo "line 1" > notes.txt && git add notes.txt && git commit -q -m "Add notes.txt"'
run 'echo "line 2" >> notes.txt'
run 'git status --short'
echo "# git commit -m alone: the modified file is NOT staged, so nothing is committed"
run 'git commit -m "Try commit -m without add" || true'
echo "# git commit -a -m: stages every TRACKED modified file, then commits"
run 'git commit -a -m "Commit with -a"'
run 'echo "new" > untracked.txt && echo "line 3" >> notes.txt'
run 'git status --short'
echo "# -a ignores untracked files: only notes.txt is committed"
run 'git commit -a -m "Commit -a again"'
run 'git status --short'
run 'rm untracked.txt'

echo "### Task 2: cherry-pick"
run 'echo "home" > home.html && git add home.html && git commit -q -m "main: add home page"'
run 'echo "about" > about.html && git add about.html && git commit -q -m "main: add about page"'
run 'git log --oneline'
run 'git switch -c feature'
run 'echo "login" > login.html && git add login.html && git commit -q -m "feature: add login page"'
run 'echo "bugfix: typo in home" > home.html && git commit -q -a -m "feature: fix typo on home page"'
run 'echo "dashboard" > dashboard.html && git add dashboard.html && git commit -q -m "feature: add dashboard"'
run 'git log --oneline main..feature'
FIX=$(git log --format=%h --grep="fix typo" feature)
run 'git switch main'
run "git cherry-pick $FIX"
run 'git log --oneline'
echo "# Verify: the fix is in main, but login/dashboard are not"
run 'cat home.html'
run 'ls'
run 'git log --oneline --graph --all'
