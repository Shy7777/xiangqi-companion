#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_PATH="$BUILD_DIR/象棋伴练 开源版.app"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/XiangqiCompanion"
RESOURCE_DIR="$APP_PATH/Contents/Resources"
SOURCES=("$PROJECT_DIR"/Sources/*.swift)

fail() {
  printf '构建失败：%s\n' "$*" >&2
  exit 1
}

[[ "$(/usr/bin/uname -m)" == "arm64" ]] || fail "当前构建目标为 Apple Silicon Mac。"
for source_file in "${SOURCES[@]}" "$PROJECT_DIR/Info.plist" "$PROJECT_DIR/LICENSE" "$PROJECT_DIR/Docs/UPSTREAM-NOTICES.txt"; do
  [[ -f "$source_file" ]] || fail "缺少文件：$source_file"
done

SWIFTC="$(/usr/bin/xcrun --find swiftc)" || fail "需要本机的 Apple Command Line Tools。"
SDK_PATH="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)" || fail "无法找到 macOS SDK。"
/usr/bin/plutil -lint "$PROJECT_DIR/Info.plist" >/dev/null
/bin/mkdir -p "$BUILD_DIR"

needs_build=false
for input_file in "${SOURCES[@]}" "$PROJECT_DIR/Info.plist" "$PROJECT_DIR/build.sh"; do
  if [[ ! -x "$EXECUTABLE_PATH" || "$input_file" -nt "$EXECUTABLE_PATH" ]]; then
    needs_build=true
  fi
done

if [[ "$needs_build" == true ]]; then
  printf '正在构建象棋伴练…\n'
  BUILD_TEMP_DIR="$(/usr/bin/mktemp -d -t xiangqi-build)" || fail "无法创建本次构建的临时目录。"
  cleanup_build_temp() {
    # Only remove the unique directory created by this invocation. Old build
    # caches and user data are deliberately outside this cleanup's scope.
    case "$BUILD_TEMP_DIR" in
      */xiangqi-build.*)
        [[ -d "$BUILD_TEMP_DIR" && ! -L "$BUILD_TEMP_DIR" ]] && /bin/rm -rf -- "$BUILD_TEMP_DIR"
        ;;
    esac
    return 0
  }
  trap cleanup_build_temp EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  /bin/mkdir -p "$BUILD_TEMP_DIR/module-cache" "$BUILD_TEMP_DIR/tmp"
  TMPDIR="$BUILD_TEMP_DIR/tmp/" \
  CLANG_MODULE_CACHE_PATH="$BUILD_TEMP_DIR/module-cache" \
  SWIFT_MODULECACHE_PATH="$BUILD_TEMP_DIR/module-cache" \
  "$SWIFTC" \
    -swift-version 5 \
    -parse-as-library \
    -O \
    -whole-module-optimization \
    -target arm64-apple-macosx13.0 \
    -sdk "$SDK_PATH" \
    -module-cache-path "$BUILD_TEMP_DIR/module-cache" \
    -framework SwiftUI \
    -framework AppKit \
    -framework Foundation \
    -framework WebKit \
    "${SOURCES[@]}" \
    -o "$BUILD_TEMP_DIR/XiangqiCompanion"
  /bin/mkdir -p "$APP_PATH/Contents/MacOS"
  /bin/mv -f "$BUILD_TEMP_DIR/XiangqiCompanion" "$EXECUTABLE_PATH"
fi

# This public build never bundles an engine, NNUE, book, or private archive.
[[ ! -e "$RESOURCE_DIR/engine" ]] || fail "此产物含旧引擎目录，请使用干净的公开版构建目录。"
/bin/mkdir -p "$RESOURCE_DIR/Notices/licenses"

bundle_changed="$needs_build"
copy_resource() {
  local source_file="$1"
  local destination_file="$2"
  if [[ ! -f "$destination_file" || "$source_file" -nt "$destination_file" ]]; then
    # Copy file contents into this project build; never alter the downloaded originals.
    /bin/cp -X "$source_file" "$destination_file"
    bundle_changed=true
  fi
}

copy_resource "$PROJECT_DIR/Info.plist" "$APP_PATH/Contents/Info.plist"
copy_resource "$PROJECT_DIR/LICENSE" "$RESOURCE_DIR/Notices/LICENSE"
copy_resource "$PROJECT_DIR/Docs/UPSTREAM-NOTICES.txt" "$RESOURCE_DIR/Notices/UPSTREAM-NOTICES.txt"
for license_file in "$PROJECT_DIR"/Docs/licenses/*.txt; do
  [[ -f "$license_file" ]] || fail "缺少第三方许可证文本。"
  copy_resource "$license_file" "$RESOURCE_DIR/Notices/licenses/$(/usr/bin/basename "$license_file")"
done

/bin/chmod 755 "$EXECUTABLE_PATH"
if [[ "$bundle_changed" == true ]] || ! /usr/bin/codesign --verify --deep --strict "$APP_PATH" 2>/dev/null; then
  /usr/bin/codesign --force --sign - --timestamp=none "$APP_PATH"
fi
/usr/bin/codesign --verify --deep --strict "$APP_PATH"
printf '应用已就绪：%s\n' "$APP_PATH"
