; MyCalls Windows installer (gerado fora da árvore do app)
!include "MUI2.nsh"

!define APP_NAME "MyCalls"
!define COMPANY "MyCalls"
!define VERSION "1.0.10"
!define BUNDLE "/home/michel/Flutter/MyCalls/build/win_cross/release/mycalls_app"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\MyCalls"

Name "${APP_NAME} ${VERSION}"
OutFile "/home/michel/Flutter/MyCalls/pacotes/MyCalls-Setup-${VERSION}.exe"
InstallDir "$PROGRAMFILES64\${APP_NAME}"
InstallDirRegKey HKLM "${UNINST_KEY}" "InstallLocation"
RequestExecutionLevel admin
SetCompressor /SOLID lzma

!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "PortugueseBR"

Section "Install"
  SetOutPath "$INSTDIR"
  File /r "${BUNDLE}\*.*"

  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\MyCalls.exe"
  CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\MyCalls.exe"

  WriteRegStr HKLM "${UNINST_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "${UNINST_KEY}" "Publisher" "${COMPANY}"
  WriteRegStr HKLM "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINST_KEY}" "UninstallString" "$INSTDIR\Uninstall.exe"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
SectionEnd

Section "Uninstall"
  RMDir /r "$INSTDIR"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"
  Delete "$DESKTOP\${APP_NAME}.lnk"
  DeleteRegKey HKLM "${UNINST_KEY}"
SectionEnd
