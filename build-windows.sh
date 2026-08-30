#!/usr/bin/env bash
# Cross-build do MyCalls para Windows (x64) a partir do Linux — Rota C.
# Requisitos (todos em nível de usuário, sem sudo):
#   - Flutter global + wine + nsis + llvm-mingw (/opt/llvm-mingw)
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

FLUTTER_VERSION="$(flutter --version | sed -nE 's/^Flutter ([^ ]+).*/\1/p' | head -n 1)"
if [[ ! "$FLUTTER_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  echo "Erro: não foi possível identificar a versão do Flutter." >&2
  exit 1
fi

BUILD="${BUILD:-$PWD/build/win_cross/release/cmake_build/sidecar/import}"
export SIDECAR_IMPORT_LIBS="$BUILD/flutter_webrtc_plugin_import.lib;$BUILD/livekit_client_plugin_import.lib;$BUILD/permission_handler_windows_plugin_import.lib;$BUILD/share_plus_plugin_import.lib;$BUILD/connectivity_plus_plugin_import.lib;$BUILD/flutter_secure_storage_windows_plugin_import.lib;$BUILD/audioplayers_windows_plugin_import.lib"

flutter_build windows --release -D "MYCALLS_FLUTTER_VERSION=$FLUTTER_VERSION"

echo "Bundle: build/win_cross/release/mycalls_app/"

# ── Pacote portátil .zip → pacotes/ ──
VERSION=$(grep -m1 '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//' | cut -d+ -f1)
BUNDLE_DIR="build/win_cross/release/mycalls_app"
ZIP_OUT="pacotes/MyCalls-${VERSION}-windows-portable.zip"
ROOT="$(pwd)"
mkdir -p pacotes
CACHE_DIR="build/win_cross/release/package_cache"
mkdir -p "$CACHE_DIR"

# Metadata is sufficient here because every build stage preserves destination
# mtimes when an artifact did not change. This avoids hashing 100+ MiB on every
# incremental invocation while still detecting additions, removals and updates.
BUNDLE_FINGERPRINT=$(
  find "$BUNDLE_DIR" -type f -printf '%P\0%s\0%T@\0' |
    LC_ALL=C sort -z |
    sha256sum |
    cut -d' ' -f1
)

ZIP_STAMP="$CACHE_DIR/portable-zip.inputs"
ZIP_FINGERPRINT=$(printf 'portable-zip-v2\0%s\0%s' "$VERSION" "$BUNDLE_FINGERPRINT" | sha256sum | cut -d' ' -f1)
if [[ -f "$ZIP_OUT" && -f "$ZIP_STAMP" && "$(<"$ZIP_STAMP")" == "$ZIP_FINGERPRINT" ]]; then
  echo "Zip portátil não mudou; reutilizando: $ZIP_OUT"
else
  (
    cd "$BUNDLE_DIR" &&
    bsdtar -a -cf "$ROOT/$ZIP_OUT" -- *.exe *.dll data
  )
  printf '%s' "$ZIP_FINGERPRINT" >"$ZIP_STAMP.tmp"
  mv "$ZIP_STAMP.tmp" "$ZIP_STAMP"
  echo "Zip portátil: $ZIP_OUT"
fi

if command -v makensis >/dev/null && [[ "${INSTALLER:-0}" == "1" ]]; then
  INSTALLER_OUT="pacotes/MyCalls-Setup-${VERSION}.exe"
  INSTALLER_STAMP="$CACHE_DIR/installer.inputs"
  NSI_FINGERPRINT=$(sha256sum scripts/installer.nsi | cut -d' ' -f1)
  INSTALLER_FINGERPRINT=$(printf 'nsis-installer-v2\0%s\0%s\0%s' "$VERSION" "$BUNDLE_FINGERPRINT" "$NSI_FINGERPRINT" | sha256sum | cut -d' ' -f1)
  if [[ -f "$INSTALLER_OUT" && -f "$INSTALLER_STAMP" && "$(<"$INSTALLER_STAMP")" == "$INSTALLER_FINGERPRINT" ]]; then
    echo "Instalador não mudou; reutilizando: $INSTALLER_OUT"
  else
    makensis \
      "-DVERSION=${VERSION}" \
      "-DBUNDLE=${ROOT}/${BUNDLE_DIR}" \
      "-DOUTPUT_DIR=${ROOT}/pacotes" \
      scripts/installer.nsi >/dev/null
    printf '%s' "$INSTALLER_FINGERPRINT" >"$INSTALLER_STAMP.tmp"
    mv "$INSTALLER_STAMP.tmp" "$INSTALLER_STAMP"
    echo "Instalador: $INSTALLER_OUT"
  fi
fi
