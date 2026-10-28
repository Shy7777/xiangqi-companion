#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! "$PROJECT_DIR/build.sh"; then
  printf '启动失败：请查看构建错误。需要 Apple Silicon Mac 和 Apple Command Line Tools。\n' >&2
  exit 1
fi

/usr/bin/open "$PROJECT_DIR/build/象棋伴练 开源版.app"
# The native app owns its engine process. This launcher exits immediately.
exit 0
