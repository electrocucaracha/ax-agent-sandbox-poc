#!/bin/sh
# Builds a repo with many commits so shell commands such as `git log --stat` produce large output.
set -e
git config --global --add safe.directory '*'
git config --global user.email demo@example.com && git config --global user.name demo
mkdir -p /opt/demo-repo && cd /opt/demo-repo && git init -q
for i in $(seq 1 120); do
  mkdir -p "src/mod$((i % 12))"
  seq 1 $((i % 7 + 3)) > "src/mod$((i % 12))/file$i.txt"
  echo "change $i" >> notes.txt
  git add -A && git commit -q -m "feat: change number $i in module $((i % 12))"
done
