#!/bin/bash
# Restores *.bak-shadow1 backups created by apply-shadows.sh
set -euo pipefail
n=0
for f in $(find /usr/share/omarchy/shell /usr/share/omarchy/default/themed -name "*.bak-shadow1" 2>/dev/null); do
  mv "$f" "${f%.bak-shadow1}"; n=$((n+1)); echo "restored: ${f%.bak-shadow1}"
done
echo "restored $n files"
