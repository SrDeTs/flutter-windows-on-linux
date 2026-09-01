; MyCalls Windows installer (gerado fora da árvore do app)
!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"
!include "WinMessages.nsh"

!define APP_NAME "MyCalls"
!define COMPANY "MyCalls"
!ifndef VERSION
  !error "VERSION deve ser informado pelo script de build"
!endif
!ifndef BUNDLE
  !error "BUNDLE deve ser informado pelo script de build"
!endif
!ifndef OUTPUT_DIR
  !error "OUTPUT_DIR deve ser informado pelo script de build"
!endif
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\MyCalls"

Name "${APP_NAME} ${VERSION}"
OutFile "${OUTPUT_DIR}/MyCalls-Setup-${VERSION}.exe"
InstallDir "$PROGRAMFILES64\${APP_NAME}"
InstallDirRegKey HKLM "${UNINST_KEY}" "InstallLocation"
; Keep the executable launchable by clients older than build 18, which used
; CreateProcess and failed with ERROR_ELEVATION_REQUIRED. The bootstrap starts
; as the current user and explicitly relaunches itself through the UAC prompt.
RequestExecutionLevel user
SetCompressor /SOLID lzma

!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "PortugueseBR"

Function .onInit
  ${GetParameters} $R0
  ClearErrors
  ${GetOptions} $R0 "/ELEVATED" $R1
  ${If} ${Errors}
    ClearErrors
    ExecShell "runas" "$EXEPATH" "/ELEVATED"
    Quit
  ${EndIf}
FunctionEnd

Section "Install"
  ; The updater launches this installer from MyCalls. Ask the running app to
  ; close before replacing its executable and DLLs.
  FindWindow $0 "FLUTTER_RUNNER_WIN32_WINDOW" "MyCalls"
  ${If} $0 != 0
    SendMessage $0 ${WM_CLOSE} 0 0 /TIMEOUT=5000
    Sleep 500
  ${EndIf}

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
