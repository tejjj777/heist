@echo off
setlocal
for %%I in ("%~dp0..\..\..\sdk\android\platform-tools\adb.exe") do set "HEIST_ADB=%%~fI"
for %%I in ("%~dp0..\build\app\outputs\flutter-apk\app-release.apk") do set "HEIST_APK=%%~fI"
set "HEIST_LOG=%TEMP%\heist-phone-install.log"
if not exist "%HEIST_ADB%" goto missing
if not exist "%HEIST_APK%" goto missing
>"%HEIST_LOG%" echo HEIST phone deployment
echo Keep the Moto unlocked. Approve Allow USB debugging if prompted.
"%HEIST_ADB%" start-server >>"%HEIST_LOG%" 2>&1
if errorlevel 1 goto failed
"%HEIST_ADB%" -d get-state >>"%HEIST_LOG%" 2>&1
if errorlevel 1 goto failed
"%HEIST_ADB%" -d shell getprop ro.product.manufacturer 2>>"%HEIST_LOG%" | findstr /i "motorola" >nul
if errorlevel 1 (
  >>"%HEIST_LOG%" echo The USB phone was not identified as Motorola. Installation stopped.
  goto failed
)
echo Installing HEIST. Approve installation on the phone if prompted.
"%HEIST_ADB%" -d install -r "%HEIST_APK%" >>"%HEIST_LOG%" 2>&1
if errorlevel 1 goto failed
"%HEIST_ADB%" -d shell am start -W -n io.github.tejjj777.heist.flutter/com.example.heist_flutter.MainActivity >>"%HEIST_LOG%" 2>&1
if errorlevel 1 goto failed
"%HEIST_ADB%" -d shell pidof io.github.tejjj777.heist.flutter >>"%HEIST_LOG%" 2>&1
if errorlevel 1 goto failed
>>"%HEIST_LOG%" echo APP_STARTED_AND_RUNNING
type "%HEIST_LOG%"
echo HEIST is installed and running. Keep this window open.
pause
exit /b 0
:failed
type "%HEIST_LOG%"
echo Installation has not been verified. Leave this window open for diagnosis.
pause
exit /b 1
:missing
echo The workspace Android SDK or HEIST APK was not found.
pause
exit /b 1
