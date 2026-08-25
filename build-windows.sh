#!/usr/bin/env bash
# Cross-build do MyCalls para Windows (x64) a partir do Linux — Rota C.
# Requisitos (todos em nível de usuário, sem sudo):
#   - FVM Flutter stable + wine + nsis + llvm-mingw (/opt/llvm-mingw)
#   - ~/.msvc2  → MSVC+SDK+ATL via msvc-wine/vsdownload.py + install.sh
#   - ~/.cppwinrt/include → projeções C++/WinRT geradas por cppwinrt.exe (wine)
#   - .opencode/flutter_build ativado: dart pub global activate --source path .
set -euo pipefail
cd "$(dirname "$0")/.."

export PATH="$PATH:$HOME/.pub-cache/bin:/opt/llvm-mingw/bin"
export LLVM_MINGW_ROOT=/opt/llvm-mingw
export CPPWINRT_INCLUDE_DIR="$HOME/.cppwinrt/include"
export SIDECAR_MSVC=1
export MSVC_ROOT="$HOME/.msvc2"
export WINEDEBUG=-all
export FLUTTER_BUILD_DLL_SEARCH_ROOT=/nonexistent  # desliga o scan amplo de DLLs

BUILD="${BUILD:-$PWD/build/win_cross/release/cmake_build/sidecar/import}"
export SIDECAR_IMPORT_LIBS="$BUILD/flutter_webrtc_plugin_import.lib;$BUILD/livekit_client_plugin_import.lib;$BUILD/permission_handler_windows_plugin_import.lib;$BUILD/share_plus_plugin_import.lib;$BUILD/connectivity_plus_plugin_import.lib;$BUILD/flutter_secure_storage_windows_plugin_import.lib"

MYCALLS_API_URL="${MYCALLS_API_URL:-https://api.mycalls.shop}"
LIVEKIT_WS_URL="${LIVEKIT_WS_URL:-wss://rtc.mycalls.shop}"

flutter_build windows --release \
  --dart-define=MYCALLS_API_URL="$MYCALLS_API_URL" \
  --dart-define=MYCALLS_FILE_SERVER_URL="$MYCALLS_API_URL" \
  --dart-define=LIVEKIT_WS_URL="$LIVEKIT_WS_URL" \
  --dart-define=LIVEKIT_TOKEN_API_URL="$MYCALLS_API_URL/api/v1/livekit/token"

echo "Bundle: build/win_cross/release/mycalls_app/"

# ── Pacote portátil .zip → pacotes/ ──
VERSION=$(grep -m1 '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//' | cut -d+ -f1)
BUNDLE_DIR="build/win_cross/release/mycalls_app"
ZIP_OUT="pacotes/MyCalls-${VERSION}-windows-portable.zip"
ROOT="$(pwd)"
mkdir -p pacotes
(
  cd "$BUNDLE_DIR" &&
  bsdtar -a -cf "$ROOT/$ZIP_OUT" -- *.exe *.dll data
)
echo "Zip portátil: $ZIP_OUT"

if command -v makensis >/dev/null && [[ "${INSTALLER:-0}" == "1" ]]; then
  mkdir -p pacotes
  makensis scripts/installer.nsi >/dev/null
  echo "Instalador: pacotes/MyCalls-Setup-${VERSION}.exe"
fi
