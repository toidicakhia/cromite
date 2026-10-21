; chrome-win7.nsi - NSIS installer for the Cromite Windows 7 build.
;
; Built by scripts/10-installer.sh, which passes:
;   -DPRODUCT_VERSION=153.0.8010.37
;   -DSTAGE_DIR=<dir containing chrome.exe, chrome.dll, locales/...>
;   -DOUT_FILE=<path to output setup exe>
;   -DESTIMATED_SIZE_KB=<int>
;
; Per-machine install (HKLM / Program Files), like the official Chrome
; per-machine installer. Uninstalling keeps the browser profile (user data).

Unicode true
ManifestSupportedOS all

!include "MUI2.nsh"

!ifndef PRODUCT_VERSION
  !error "PRODUCT_VERSION is not defined (pass -DPRODUCT_VERSION=x.y.z.w)"
!endif
!ifndef STAGE_DIR
  !error "STAGE_DIR is not defined (pass -DSTAGE_DIR=<packaged chrome-win dir>)"
!endif
!ifndef OUT_FILE
  !define OUT_FILE "chrome-win7-setup.exe"
!endif
!ifndef ESTIMATED_SIZE_KB
  !define ESTIMATED_SIZE_KB 600000
!endif

!define PRODUCT_NAME "Cromite"
!define PRODUCT_PUBLISHER "Cromite (uazo)"
!define PRODUCT_EXE "chrome.exe"
!define PRODUCT_KEY "Cromite"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_KEY}"

Name "${PRODUCT_NAME} ${PRODUCT_VERSION}"
OutFile "${OUT_FILE}"
InstallDir "$PROGRAMFILES64\${PRODUCT_NAME}"
InstallDirRegKey HKLM "Software\${PRODUCT_KEY}" "InstallDir"
RequestExecutionLevel admin
BrandingText "${PRODUCT_NAME} ${PRODUCT_VERSION} (Windows 7 build)"

; LZMA gives the smallest download; the installer is built once per release.
SetCompressor /SOLID lzma
SetCompressorDictSize 64

!define MUI_ICON "chrome.ico"
!define MUI_UNICON "chrome.ico"
!define MUI_ABORTWARNING

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES

; Launch through explorer.exe so the browser does not run elevated.
; MUI requires MUI_FINISHPAGE_RUN for the checkbox; RUN_FUNCTION replaces Exec.
!define MUI_FINISHPAGE_RUN "$INSTDIR\${PRODUCT_EXE}"
!define MUI_FINISHPAGE_RUN_FUNCTION LaunchBrowser
!define MUI_FINISHPAGE_RUN_TEXT "Launch ${PRODUCT_NAME}"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

VIProductVersion "${PRODUCT_VERSION}"
VIAddVersionKey /LANG=1033 "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey /LANG=1033 "FileDescription" "${PRODUCT_NAME} Setup"
VIAddVersionKey /LANG=1033 "FileVersion" "${PRODUCT_VERSION}"
VIAddVersionKey /LANG=1033 "ProductVersion" "${PRODUCT_VERSION}"
VIAddVersionKey /LANG=1033 "LegalCopyright" "Cromite"
VIAddVersionKey /LANG=1033 "OriginalFilename" "chrome-win7-setup.exe"

Function .onInit
  ; 64-bit registry view so the browser registration is visible to the OS.
  SetRegView 64
FunctionEnd

Function un.onInit
  SetRegView 64
FunctionEnd

Function LaunchBrowser
  Exec '"$WINDIR\explorer.exe" "$INSTDIR\${PRODUCT_EXE}"'
FunctionEnd

Section "${PRODUCT_NAME} browser" SecMain
  SectionIn RO
  SetShellVarContext all
  SetRegView 64
  SetOutPath "$INSTDIR"
  File /r "${STAGE_DIR}/*"

  WriteRegStr HKLM "Software\${PRODUCT_KEY}" "InstallDir" "$INSTDIR"
  WriteRegStr HKLM "Software\${PRODUCT_KEY}" "Version" "${PRODUCT_VERSION}"

  ; Add/Remove Programs entry
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayName" "${PRODUCT_NAME} ${PRODUCT_VERSION}"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKLM "${UNINST_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\${PRODUCT_EXE},0"
  WriteRegStr HKLM "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINST_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKLM "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoRepair" 1
  WriteRegDWORD HKLM "${UNINST_KEY}" "EstimatedSize" ${ESTIMATED_SIZE_KB}

  ; Browser registration: appears in "Default Programs" so the user can pick
  ; it for http/https. Setting it as default from the browser itself also
  ; works (the browser performs its own registration when asked).
  WriteRegStr HKLM "SOFTWARE\Clients\StartMenuInternet\${PRODUCT_KEY}" "" "${PRODUCT_NAME}"
  WriteRegStr HKLM "SOFTWARE\Clients\StartMenuInternet\${PRODUCT_KEY}\DefaultIcon" "" "$INSTDIR\${PRODUCT_EXE},0"
  WriteRegStr HKLM "SOFTWARE\Clients\StartMenuInternet\${PRODUCT_KEY}\shell\open\command" "" '"$INSTDIR\${PRODUCT_EXE}"'
  WriteRegStr HKLM "SOFTWARE\Clients\StartMenuInternet\${PRODUCT_KEY}\Capabilities" "ApplicationName" "${PRODUCT_NAME}"
  WriteRegStr HKLM "SOFTWARE\Clients\StartMenuInternet\${PRODUCT_KEY}\Capabilities" "ApplicationDescription" "${PRODUCT_NAME} web browser"
  WriteRegStr HKLM "SOFTWARE\Clients\StartMenuInternet\${PRODUCT_KEY}\Capabilities" "ApplicationIcon" "$INSTDIR\${PRODUCT_EXE},0"
  WriteRegStr HKLM "SOFTWARE\Clients\StartMenuInternet\${PRODUCT_KEY}\Capabilities\URLAssociations" "http" "${PRODUCT_KEY}URL"
  WriteRegStr HKLM "SOFTWARE\Clients\StartMenuInternet\${PRODUCT_KEY}\Capabilities\URLAssociations" "https" "${PRODUCT_KEY}URL"
  WriteRegStr HKLM "SOFTWARE\Clients\StartMenuInternet\${PRODUCT_KEY}\Capabilities\StartMenuInternet" "" "${PRODUCT_KEY}"
  WriteRegStr HKLM "SOFTWARE\RegisteredApplications" "${PRODUCT_NAME}" "SOFTWARE\Clients\StartMenuInternet\${PRODUCT_KEY}\Capabilities"
  WriteRegStr HKLM "SOFTWARE\Classes\${PRODUCT_KEY}URL" "" "${PRODUCT_NAME} URL"
  WriteRegStr HKLM "SOFTWARE\Classes\${PRODUCT_KEY}URL" "URL Protocol" ""
  WriteRegStr HKLM "SOFTWARE\Classes\${PRODUCT_KEY}URL\DefaultIcon" "" "$INSTDIR\${PRODUCT_EXE},0"
  WriteRegStr HKLM "SOFTWARE\Classes\${PRODUCT_KEY}URL\shell\open\command" "" '"$INSTDIR\${PRODUCT_EXE}" -- "%1"'

  ; Win+R support
  WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" "" "$INSTDIR\${PRODUCT_EXE}"
  WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" "Path" "$INSTDIR"

  ; Start Menu shortcuts
  CreateDirectory "$SMPROGRAMS\${PRODUCT_NAME}"
  CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME}.lnk" "$INSTDIR\${PRODUCT_EXE}" "" "$INSTDIR\${PRODUCT_EXE}" 0
  CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\Uninstall ${PRODUCT_NAME}.lnk" "$INSTDIR\uninstall.exe"

  WriteUninstaller "$INSTDIR\uninstall.exe"
SectionEnd

Section "Desktop shortcut" SecDesktop
  SetShellVarContext all
  CreateShortCut "$DESKTOP\${PRODUCT_NAME}.lnk" "$INSTDIR\${PRODUCT_EXE}" "" "$INSTDIR\${PRODUCT_EXE}" 0
SectionEnd

Section "Uninstall"
  SetShellVarContext all
  SetRegView 64

  Delete "$DESKTOP\${PRODUCT_NAME}.lnk"
  Delete "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME}.lnk"
  Delete "$SMPROGRAMS\${PRODUCT_NAME}\Uninstall ${PRODUCT_NAME}.lnk"
  RMDir "$SMPROGRAMS\${PRODUCT_NAME}"

  RMDir /r "$INSTDIR"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"

  DeleteRegKey HKLM "${UNINST_KEY}"
  DeleteRegKey HKLM "Software\${PRODUCT_KEY}"
  DeleteRegKey HKLM "SOFTWARE\Clients\StartMenuInternet\${PRODUCT_KEY}"
  DeleteRegValue HKLM "SOFTWARE\RegisteredApplications" "${PRODUCT_NAME}"
  DeleteRegKey HKLM "SOFTWARE\Classes\${PRODUCT_KEY}URL"
  DeleteRegKey HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe"
SectionEnd
