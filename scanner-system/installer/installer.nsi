; Scanner Management System Installer
; Enterprise intranet deployment

!define PRODUCT_NAME "Scanner Management"
!define PRODUCT_VERSION "2.0.0"
!define PRODUCT_PUBLISHER "Scanner Local Service"
!define PRODUCT_WEBVIEW2_GUID "{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
!define PRODUCT_UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"
!define INSTALL_DIR "Scanner"

Name "${PRODUCT_NAME} ${PRODUCT_VERSION}"
OutFile "..\release\Scanner_${PRODUCT_VERSION}_x64-setup.exe"
InstallDir "C:\Program Files\${INSTALL_DIR}"
RequestExecutionLevel admin

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"

!define MUI_ABORTWARNING
!define MUI_ICON "..\tauri\src-tauri\icons\icon.ico"
!define MUI_UNICON "..\tauri\src-tauri\icons\icon.ico"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "..\LICENSE.txt"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\scanner-client.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Start Scanner Management"
!define MUI_FINISHPAGE_NOREBOOTSUPPORT
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "SimpChinese"

Section "MainApplication" SEC_MAIN
    SectionIn RO
    SetOutPath "$INSTDIR"
    ExecWait 'taskkill /f /im scanner-client.exe' $0

    ; Tauri desktop shell
    File "..\tauri\src-tauri\target\release\scanner-client.exe"

    ; Backend (Spring Boot + JRE + lib)
    SetOutPath "$INSTDIR\backend"
    File /r "..\backend\*.*"

    ; WebView2 offline installer (embedded)
    SetOutPath "$INSTDIR"
    File "runtime\WebView2Offline.exe"

    ; Shortcuts
    CreateDirectory "$SMPROGRAMS\${PRODUCT_NAME}"
    CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME}.lnk" "$INSTDIR\scanner-client.exe"
    CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\Uninstall.lnk" "$INSTDIR\Uninstall.exe"
    CreateShortCut "$DESKTOP\${PRODUCT_NAME}.lnk" "$INSTDIR\scanner-client.exe"

    ; Uninstall info
    WriteUninstaller "$INSTDIR\Uninstall.exe"
    WriteRegStr HKLM "${PRODUCT_UNINSTALL_KEY}" "DisplayName" "${PRODUCT_NAME}"
    WriteRegStr HKLM "${PRODUCT_UNINSTALL_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
    WriteRegStr HKLM "${PRODUCT_UNINSTALL_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
    WriteRegStr HKLM "${PRODUCT_UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKLM "${PRODUCT_UNINSTALL_KEY}" "UninstallString" "$INSTDIR\Uninstall.exe"
    WriteRegStr HKLM "${PRODUCT_UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\scanner-client.exe"
    WriteRegDWORD HKLM "${PRODUCT_UNINSTALL_KEY}" "NoModify" 1
    WriteRegDWORD HKLM "${PRODUCT_UNINSTALL_KEY}" "NoRepair" 1
    ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
    WriteRegDWORD HKLM "${PRODUCT_UNINSTALL_KEY}" "EstimatedSize" "$0"

    ; --- WebView2 detect + install ---
    ReadRegStr $0 HKLM "SOFTWARE\Microsoft\EdgeUpdate\Clients\${PRODUCT_WEBVIEW2_GUID}" "pv"
    ${If} $0 == ""
        ReadRegStr $0 HKLM "SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\${PRODUCT_WEBVIEW2_GUID}" "pv"
    ${EndIf}

    ${If} $0 == ""
        DetailPrint "Installing WebView2 Runtime..."
        ExecWait '"$INSTDIR\WebView2Offline.exe" /silent /install' $0
        ${If} $0 != 0
            DetailPrint "WebView2 exit: $0"
            MessageBox MB_YESNO|MB_ICONQUESTION \
                "WebView2 install failed ($0). Download from Microsoft?" \
                /SD IDYES IDYES dl_wv2 IDNO skip_wv2
            dl_wv2:
            DetailPrint "Downloading WebView2 Runtime..."
            NSISdl::download "https://go.microsoft.com/fwlink/p/?LinkId=2124703" \
                "$TEMP\WebView2Offline.exe"
            Pop $0
            ${If} $0 == "success"
                ExecWait '"$TEMP\WebView2Offline.exe" /silent /install' $0
            ${EndIf}
            skip_wv2:
        ${Else}
            DetailPrint "WebView2 install complete"
        ${EndIf}
    ${Else}
        DetailPrint "WebView2 Runtime already installed"
    ${EndIf}
    Delete "$INSTDIR\WebView2Offline.exe"
SectionEnd

Section "Uninstall"
    SetShellVarContext all
    ExecWait 'taskkill /f /im scanner-client.exe' $0
    ExecWait 'taskkill /f /im java.exe' $0
    Delete "$DESKTOP\${PRODUCT_NAME}.lnk"
    RMDir /r "$SMPROGRAMS\${PRODUCT_NAME}"
    RMDir /r "$INSTDIR"
    DeleteRegKey HKLM "${PRODUCT_UNINSTALL_KEY}"
SectionEnd