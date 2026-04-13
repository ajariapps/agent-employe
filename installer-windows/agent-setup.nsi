; Employee Monitoring Agent - Windows Installer Script
; Requires NSIS 3.0+ (https://nsis.sourceforge.io/)

!include "MUI2.nsh"
!include "x64.nsh"

; -------------------------------------
; Configuration
; -------------------------------------
!define APP_NAME "Employee Monitoring Agent"
!define APP_EXECUTABLE "agent.exe"
!define APP_SERVICE_NAME "AgentRust"
!define APP_SERVICE_DISPLAY "Employee Monitoring Agent"
!define COMP_NAME "Ajari Apps"
!define VERSION "1.0.0"

; Install directory
!define DEFAULT_INSTALL_DIR "$PROGRAMFILES\AgentRust"

; Output file
!define OUTPUT_FILE "Agent-Setup.exe"

; -------------------------------------
; General
; -------------------------------------
Name "${APP_NAME}"
OutFile "${OUTPUT_FILE}"
InstallDir "${DEFAULT_INSTALL_DIR}"
RequestExecutionLevel admin
ShowInstDetails show
ShowUnInstDetails show

; -------------------------------------
; Interface Settings
; -------------------------------------
!define MUI_ABORTWARNING
!define MUI_ICON "agent.ico"
!define MUI_UNICON "agent.ico"
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_RIGHT

; -------------------------------------
; Pages
; -------------------------------------
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "license.txt"
!insertmacro MUI_PAGE_DIRECTORY
Page custom ServerURLPage
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

; -------------------------------------
; Languages
; -------------------------------------
!insertmacro MUI_LANGUAGE "English"

; -------------------------------------
; Installer Sections
; -------------------------------------
Section "Agent" SecAgent
    SectionIn RO

    ; Set output path
    SetOutPath $INSTDIR

    ; Display installation status
    DetailPrint "Installing ${APP_NAME}..."

    ; Extract files
    File "${APP_EXECUTABLE}"

    ; Create uninstaller
    WriteUninstaller "$INSTDIR\uninstall.exe"

    ; Write registry keys for Add/Remove Programs
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_SERVICE_NAME}" "DisplayName" "${APP_NAME}"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_SERVICE_NAME}" "DisplayVersion" "${VERSION}"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_SERVICE_NAME}" "Publisher" "${COMP_NAME}"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_SERVICE_NAME}" "UninstallString" "$INSTDIR\uninstall.exe"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_SERVICE_NAME}" "QuietUninstallString" "$INSTDIR\uninstall.exe /S"
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_SERVICE_NAME}" "NoModify" 1
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_SERVICE_NAME}" "NoRepair" 1

    ; Get server URL from custom page
    ReadIniStr $0 "$PLUGINSDIR\serverurl.ini" "Field 1" "State"

    ; Create Windows service
    DetailPrint "Creating Windows service..."
    nsExec::ExecToLog 'sc.exe create ${APP_SERVICE_NAME} binPath= "$INSTDIR\${APP_EXECUTABLE} run --server-url $0" DisplayName= "${APP_SERVICE_DISPLAY}" start= auto'
    Pop $0

    ; Set service description
    DetailPrint "Configuring service..."
    nsExec::ExecToLog 'sc.exe description ${APP_SERVICE_NAME} "Cross-platform employee monitoring agent"'
    Pop $0

    ; Set service to run as Local System
    nsExec::ExecToLog 'sc.exe config ${APP_SERVICE_NAME} obj= LocalSystem'
    Pop $0

    ; Set environment variable for server URL
    nsExec::ExecToLog 'sc.exe config ${APP_SERVICE_NAME} Env= "AGENT_SERVER_URL=$0"'
    Pop $0

    ; Start the service
    DetailPrint "Starting service..."
    nsExec::ExecToLog 'net start ${APP_SERVICE_NAME}'
    Pop $0

    ; Create log directory
    CreateDirectory "$APPDATA\AgentRust\logs"

    DetailPrint "Installation complete!"
SectionEnd

; -------------------------------------
; Uninstaller Section
; -------------------------------------
Section "Uninstall"
    ; Stop and remove service
    DetailPrint "Stopping service..."
    nsExec::ExecToLog 'net stop ${APP_SERVICE_NAME}'
    Pop $0

    DetailPrint "Removing service..."
    nsExec::ExecToLog 'sc.exe delete ${APP_SERVICE_NAME}'
    Pop $0

    ; Delete files
    Delete $INSTDIR\${APP_EXECUTABLE}
    Delete $INSTDIR\uninstall.exe

    ; Delete directories
    RMDir $INSTDIR

    ; Delete registry keys
    DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_SERVICE_NAME}"

    DetailPrint "Uninstallation complete!"
SectionEnd

; -------------------------------------
; Custom Page Functions
; -------------------------------------
Function ServerURLPage
    !insertmacro MUI_HEADER_TEXT "Server Configuration" "Enter your monitoring server URL"

    ; Create dialog
    nsDialogs::Create 1018
    Pop $0

    ${NSD_CreateLabel} 0 0 100% 12u "Enter the URL of your monitoring server:"
    Pop $0

    ${NSD_CreateText} 0 20u 100% 12u "http://localhost:8080"
    Pop $1

    ${NSD_CreateLabel} 0 45u 100% 24u "Example: http://192.168.1.100:8080 or https://monitoring.company.com"
    Pop $0
    SetCtlColors $0 "" ""  ; Transparent background

    ; Save state to INI file
    nsDialogs::Show
    ${NSD_GetText} $1 $0
    WriteIniStr '$PLUGINSDIR\serverurl.ini' 'Field 1' 'State' $0
FunctionEnd

Function .onInit
    ; Check if already installed
    ReadRegStr $0 HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_SERVICE_NAME}" "UninstallString"
    StrCmp $0 "" done

    ; If already installed, show message
    MessageBox MB_OKCANCEL|MB_ICONEXCLAMATION \
        "${APP_NAME} is already installed. $\n$\nClick OK to remove the previous version or Cancel to cancel this upgrade." \
        IDOK uninst
    Abort

    uninst:
    ; Run uninstaller
    ClearErrors
    ExecWait '$0 _?=$INSTDIR'

    IfErrors no_remove_uninstaller
    goto done

    no_remove_uninstaller:

    done:
FunctionEnd

Function un.onInit
    MessageBox MB_YESNO|MB_ICONQUESTION \
        "Are you sure you want to remove $(^Name) and all of its components?" \
        IDYES +2
    Abort
FunctionEnd

; -------------------------------------
; Section Descriptions
; -------------------------------------
LangString DESC_SecAgent ${LANG_ENGLISH} "Install Employee Monitoring Agent"

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
!insertmacro MUI_DESCRIPTION_TEXT ${SecAgent} $(DESC_SecAgent)
!insertmacro MUI_FUNCTION_DESCRIPTION_END
