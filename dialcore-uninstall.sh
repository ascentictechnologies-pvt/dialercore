#!/usr/bin/env bash
# DialCore uninstaller: removes what dialcore-install.sh installed (same as: dialcore-install.sh uninstall).
#   sudo ./dialcore-uninstall.sh [--dry-run] [--verbose]
exec "$(dirname "${BASH_SOURCE[0]}")/dialcore-install.sh" uninstall "$@"
