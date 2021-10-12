#!/bin/bash
if command -v pod2markdown >/dev/null 2>&1; then
  pod2markdown lib.sh > README.md
else
  echo "install /usr/bin/pod2markdown"
  exit 1
fi
