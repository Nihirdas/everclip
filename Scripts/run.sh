#!/usr/bin/env bash
#
# Builds a debug EverClip.app and launches it.
#
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/Scripts/build-app.sh" debug
open "$ROOT/build/EverClip.app"
