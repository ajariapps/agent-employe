; Employee Monitoring Agent - Windows Installer Script (Enhanced)
; Requires NSIS 3.0+ (https://nsis.sourceforge.io/)

!include "MUI2.nsh"
!include "x64.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"

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
!define DEFAULT_INSTALL_DIR "$PROGRAMFILES64\AgentRust"
!define CONFIG_DIR "$APPDATA\AgentRust"
!define LOG_DIR "$APPDATA\AgentRust\logs"
!define DATA_DIR "$APPDATA\AgentRust\data"

; Output file
!define OUTPUT_FILE "Agent-Setup.exe"

; Registry keys
!define REG_UNINSTALL "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_SERVICE_NAME}"
!define REG_CONFIG "Software\AjariApps\AgentRust"

; -------------------------------------
; Variables
; -----
Var ServerURL
Var PreviousInstallDir
Var IsUpgrade
Var ConfigFileExists

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
Page custom ServerURLPage ServerURLPageLeave
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
    DetailPrint "Installing ${APP_NAME} ${VERSION}..."
    LogSet on

    ; Check if this is an upgrade
    ${If} $IsUpgrade == "1"
        DetailPrint "Previous installation detected. Preserving configuration..."
        Call StopService
    ${EndIf}

    ; Extract files
    File "${APP_EXECUTABLE}"

    ; Create directories
    CreateDirectory "${CONFIG_DIR}"
    CreateDirectory "${LOG_DIR}"
    CreateDirectory "${DATA_DIR}"

    ; Create default configuration file if it doesn't exist
    ${If} ${FileExists} "${CONFIG_DIR}\config.toml"
        DetailPrint "Existing configuration file found, preserving..."
        StrCpy $ConfigFileExists "1"
    ${Else}
        DetailPrint "Creating default configuration file..."
        Call CreateDefaultConfig
        StrCpy $ConfigFileExists "0"
    ${EndIf}

    ; Create uninstaller
    WriteUninstaller "$INSTDIR\uninstall.exe"

    ; Write registry keys for Add/Remove Programs
    WriteRegStr HKLM "${REG_UNINSTALL}" "DisplayName" "${APP_NAME}"
    WriteRegStr HKLM "${REG_UNINSTALL}" "DisplayVersion" "${VERSION}"
    WriteRegStr HKLM "${REG_UNINSTALL}" "Publisher" "${COMP_NAME}"
    WriteRegStr HKLM "${REG_UNINSTALL}" "UninstallString" "$INSTDIR\uninstall.exe"
    WriteRegStr HKLM "${REG_UNINSTALL}" "QuietUninstallString" "$INSTDIR\uninstall.exe /S"
    WriteRegStr HKLM "${REG_UNINSTALL}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKLM "${REG_UNINSTALL}" "ConfigLocation" "${CONFIG_DIR}"
    WriteRegDWORD HKLM "${REG_UNINSTALL}" "NoModify" 1
    WriteRegDWORD HKLM "${REG_UNINSTALL}" "NoRepair" 1
    WriteRegDWORD HKLM "${REG_UNINSTALL}" "VersionMajor" 1
    WriteRegDWORD HKLM "${REG_UNINSTALL}" "VersionMinor" 0

    ; Store configuration in registry
    WriteRegStr HKLM "${REG_CONFIG}" "InstallPath" "$INSTDIR"
    WriteRegStr HKLM "${REG_CONFIG}" "ConfigPath" "${CONFIG_DIR}"
    WriteRegStr HKLM "${REG_CONFIG}" "ServerURL" "$ServerURL"
    WriteRegStr HKLM "${REG_CONFIG}" "Version" "${VERSION}"

    ; Create Windows service
    DetailPrint "Creating Windows service..."
    nsExec::ExecToLog 'sc.exe create ${APP_SERVICE_NAME} binPath= "$INSTDIR\${APP_EXECUTABLE} run --config ${CONFIG_DIR}\config.toml" DisplayName= "${APP_SERVICE_DISPLAY}" start= auto'
    Pop $0

    ; Configure service recovery
    DetailPrint "Configuring service recovery..."
    nsExec::ExecToLog 'sc.exe failure ${APP_SERVICE_NAME} reset= 86400 actions= restart/5000/restart/20000/restart/60000'
    Pop $0

    ; Set service description
    DetailPrint "Configuring service description..."
    nsExec::ExecToLog 'sc.exe description ${APP_SERVICE_NAME} "Cross-platform employee monitoring agent with activity tracking and screenshot capture"'
    Pop $0

    ; Set service to run as Local System with desktop interaction disabled
    nsExec::ExecToLog 'sc.exe config ${APP_SERVICE_NAME} obj= LocalSystem type= own'
    Pop $0

    ; Start the service
    DetailPrint "Starting ${APP_SERVICE_NAME} service..."
    nsExec::ExecToLog 'net start ${APP_SERVICE_NAME}'
    Pop $0

    ; Wait for service to start
    Sleep 2000

    ; Verify service is running
    nsExec::ExecToLog 'sc.exe query ${APP_SERVICE_NAME}'
    Pop $0

    ; Create desktop shortcut (optional, for configuration access)
    CreateShortCut "$DESKTOP\Agent Configuration.lnk" "${CONFIG_DIR}" "" "" 0

    DetailPrint "Installation complete!"
    LogSet off
SectionEnd

; -------------------------------------
; Uninstaller Section
; -------------------------------------
Section "Uninstall"
    LogSet on
    DetailPrint "Starting uninstallation..."

    ; Stop and remove service
    Call un.StopService

    ; Delete service
    DetailPrint "Removing Windows service..."
    nsExec::ExecToLog 'sc.exe delete ${APP_SERVICE_NAME}'
    Pop $0

    ; Kill any remaining processes
    DetailPrint "Stopping any remaining agent processes..."
    nsExec::ExecToLog 'taskkill /F /IM ${APP_EXECUTABLE}'
    Pop $0

    ; Delete files
    DetailPrint "Removing program files..."
    Delete $INSTDIR\${APP_EXECUTABLE}
    Delete $INSTDIR\uninstall.exe
    Delete $INSTDIR\config.toml

    ; Delete shortcuts
    Delete "$DESKTOP\Agent Configuration.lnk"
    Delete "$SMPROGRAMS\${APP_NAME}.lnk"

    ; Delete directories (preserve data and logs unless full uninstall)
    RMDir $INSTDIR

    ; Ask about data removal
    MessageBox MB_YESNO|MB_ICONQUESTION \
        "Do you want to remove configuration and log files? $\n$\n(Select No to preserve data for potential reinstallation)" \
        IDYES remove_data
    goto done

    remove_data:
    DetailPrint "Removing data directories..."
    RMDir /r "${CONFIG_DIR}"
    RMDir /r "${LOG_DIR}"
    RMDir /r "${DATA_DIR}"

    done:
    ; Delete registry keys
    DeleteRegKey HKLM "${REG_UNINSTALL}"
    DeleteRegKey HKLM "${REG_CONFIG}"

    DetailPrint "Uninstallation complete!"
    LogSet off
SectionEnd

; -------------------------------------
; Helper Functions
; -------------------------------------
Function CreateDefaultConfig
    FileOpen $0 "${CONFIG_DIR}\config.toml" w
    FileWrite $0 "# Employee Monitoring Agent Configuration$\r$\n"
    FileWrite $0 "# Generated by installer on $\r$\n"
    FileWrite $0 "$\r$\n"
    FileWrite $0 "[server]$\r$\n"
    FileWrite $0 "# Server URL for API communication$\r$\n"
    FileWrite $0 "url = $\\"$ServerURL\\"$\r$\n"
    FileWrite $0 "# Request timeout in seconds$\r$\n"
    FileWrite $0 "timeout_secs = 30$\r$\n"
    FileWrite $0 "# Connection timeout in seconds$\r$\n"
    FileWrite $0 "connect_timeout_secs = 10$\r$\n"
    FileWrite $0 "# Maximum retry attempts for failed requests$\r$\n"
    FileWrite $0 "max_retries = 3$\r$\n"
    FileWrite $0 "$\r$\n"
    FileWrite $0 "[agent]$\r$\n"
    FileWrite $0 "# Data directory for storage$\r$\n"
    FileWrite $0 "data_dir = $\\"${DATA_DIR}\\"$\r$\n"
    FileWrite $0 "# Queue file path$\r$\n"
    FileWrite $0 "queue_file = $\\"${DATA_DIR}\\queue.json\\"$\r$\n"
    FileWrite $0 "$\r$\n"
    FileWrite $0 "[intervals]$\r$\n"
    FileWrite $0 "# Heartbeat interval in seconds (minimum: 10)$\r$\n"
    FileWrite $0 "heartbeat_secs = 30$\r$\n"
    FileWrite $0 "# Activity tracking interval in seconds (minimum: 5)$\r$\n"
    FileWrite $0 "activity_secs = 60$\r$\n"
    FileWrite $0 "# Screenshot interval in seconds (minimum: 30)$\r$\n"
    FileWrite $0 "screenshot_secs = 300$\r$\n"
    FileWrite $0 "$\r$\n"
    FileWrite $0 "[thresholds]$\r$\n"
    FileWrite $0 "# Idle threshold in seconds$\r$\n"
    FileWrite $0 "idle_secs = 300$\r$\n"
    FileWrite $0 "$\r$\n"
    FileWrite $0 "[logging]$\r$\n"
    FileWrite $0 "# Log level: trace, debug, info, warn, error$\r$\n"
    FileWrite $0 "level = $\\"info\\"$\r$\n"
    FileWrite $0 "# Log format: json, pretty, compact$\r$\n"
    FileWrite $0 "format = $\\"json\\"$\r$\n"
    FileWrite $0 "# Log directory$\r$\n"
    FileWrite $0 "dir = $\\"${LOG_DIR}\\"$\r$\n"
    FileWrite $0 "# Log to console$\r$\n"
    FileWrite $0 "console = true$\r$\n"
    FileWrite $0 "# Log to file$\r$\n"
    FileWrite $0 "file = true$\r$\n"
    FileClose $0

    ; Set permissions on config file
    DetailPrint "Setting configuration file permissions..."
    AccessControl::GrantOnFile "${CONFIG_DIR}\config.toml" "(BU)" "GenericRead"
    AccessControl::GrantOnFile "${CONFIG_DIR}\config.toml" "(BU)" "GenericWrite"
FunctionEnd

Function StopService
    DetailPrint "Stopping ${APP_SERVICE_NAME} service..."
    nsExec::ExecToLog 'net stop ${APP_SERVICE_NAME}'
    Pop $0
FunctionEnd

Function un.StopService
    DetailPrint "Stopping ${APP_SERVICE_NAME} service..."
    nsExec::ExecToLog 'net stop ${APP_SERVICE_NAME}'
    Pop $0

    ; Wait for service to stop
    Sleep 2000
FunctionEnd

; -------------------------------------
; Custom Page Functions
; -------------------------------------
Function ServerURLPage
    !insertmacro MUI_HEADER_TEXT "Server Configuration" "Enter your monitoring server URL"

    ; Create dialog
    nsDialogs::Create 1018
    Pop $0

    ; Title
    ${NSD_CreateLabel} 0 0 100% 20u "Enter the URL of your monitoring server:"
    Pop $0
    SendMessage $0 ${WM_SETFONT} ${DEFAULT_FONT_BOLD} 0

    ; Server URL input
    ${NSD_CreateText} 0 30u 100% 14u "http://localhost:8080"
    Pop $1

    ; Example/Help text
    ${NSD_CreateLabel} 0 55u 100% 40u "Examples:$\r$\n  - http://192.168.1.100:8080$\r$\n  - https://monitoring.company.com$\r$\n  - http://server:3000"
    Pop $0
    SetCtlColors $0 "" "${MUI_BGCOLOR}"

    ; Save state
    nsDialogs::Show
    ${NSD_GetText} $1 $ServerURL
FunctionEnd

Function ServerURLPageLeave
    ; Get the server URL from the text field
    ${NSD_GetText} $1 $ServerURL

    ; Validate URL is not empty
    ${If} $ServerURL == ""
        MessageBox MB_OK|MB_ICONEXCLAMATION "Please enter a server URL."
        Abort
    ${EndIf}

    ; Basic URL validation
    ${If} $ServerURL !~ "^(http|https)://.*"
        MessageBox MB_OK|MB_ICONEXCLAMATION "Server URL must start with http:// or https://"
        Abort
    ${EndIf}
FunctionEnd

Function .onInit
    ; Initialize variables
    StrCpy $IsUpgrade "0"
    StrCpy $ServerURL "http://localhost:8080"

    ; Check for previous installation
    ReadRegStr $PreviousInstallDir HKLM "${REG_UNINSTALL}" "UninstallString"

    ${If} $PreviousInstallDir != ""
        ; Previous installation found
        StrCpy $IsUpgrade "1"

        ; Read existing configuration
        ReadRegStr $ServerURL HKLM "${REG_CONFIG}" "ServerURL"

        ${If} $ServerURL == ""
            StrCpy $ServerURL "http://localhost:8080"
        ${EndIf}

        ; Show upgrade message
        MessageBox MB_OKCANCEL|MB_ICONQUESTION \
            "${APP_NAME} is already installed.$\n$\n\
            Current Version: $ServerURL$\n\
            New Version: ${VERSION}$\n$\n\
            Click OK to upgrade (configuration will be preserved).$\n\
            Click Cancel to exit." \
            IDOK continue_upgrade
        Abort

        continue_upgrade:
    ${EndIf}

    ; Check Windows version
    ${IfNot} ${AtLeastWin10}
        MessageBox MB_OK|MB_ICONSTOP "${APP_NAME} requires Windows 10 or later."
        Abort
    ${EndIf}

    ; Check for running instance
    System::Call 'kernel32::CreateMutexA(i 0, i 0, t "${APP_SERVICE_NAME}") i .r1 ?e'
    Pop $0
    ${If} $0 != 0
        MessageBox MB_OK|MB_ICONEXCLAMATION "The installer is already running."
        Abort
    ${EndIf}
FunctionEnd

Function un.onInit
    MessageBox MB_YESNO|MB_ICONQUESTION \
        "Are you sure you want to remove $(^Name) and all of its components?$\n$\n\
        Note: You will be given the option to preserve configuration and log files." \
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
