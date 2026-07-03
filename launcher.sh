#!/usr/bin/env bash
# WebQoLauncher entry point — tanpa argumen membuka menu interaktif
ROOT="$(cd "$(dirname "$0")" && pwd)"
if [[ $# -eq 0 ]]; then
  exec "${ROOT}/main/scripts/menu.sh"
fi
exec "${ROOT}/main/scripts/launcher.sh" "$@"
