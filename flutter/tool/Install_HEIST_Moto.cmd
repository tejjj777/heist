@echo off
setlocal
for %%I in ("%~dp0..\..\..") do set "HEIST_ROOT=%%~fI"
set "HEIST_ADB=%HEIST_ROOT%\sdk\android\platform-tools\adb.exe"
for %%I in ("%~dp0..\build\app\outputs\flutter-apk\app-release.apk") do set "HEIST_APK=%%~fI"
set "HEIST_LOG=%TEMP%\heist-phone-install.log"
>"%HEIST_LOG%" echo HEIST Moto installation started: %DATE% %TIME%
if not exist "%HEIST_ADB%" (
  >>"%HEIST_LOG%" echo ERROR: Android SDK executable not found: %HEIST_ADB%
  goto failed
)
if not exist "%HEIST_APK%" (
  >>"%HEIST_LOG%" echo ERROR: HEIST APK not found: %HEIST_APK%
  goto failed
)
echo Starting Android Debug Bridge...
"%HEIST_ADB%" start-server >>"%HEIST_LOG%" 2>&1
if errorlevel 1 goto failed
echo Keep the Moto unlocked and connected by USB.
echo Tap Allow USB debugging on the phone if prompted.
echo Waiting up to 60 seconds for authorization...
for /l %%N in (1,1,30) do (
  "%HEIST_ADB%" -d get-state >>"%HEIST_LOG%" 2>&1
  if not errorlevel 1 goto connected
  timeout /t 2 /nobreak >nul
)
>>"%HEIST_LOG%" echo ERROR: No single authorized USB phone became available.
goto failed
:connected
"%HEIST_ADB%" -d shell getprop ro.product.manufacturer 2>>"%HEIST_LOG%" | findstr /i "motorola" >nul
if errorlevel 1 (
  >>"%HEIST_LOG%" echo ERROR: The USB phone was not identified as Motorola.
  goto failed
)
echo Installing HEIST. Accept an installation prompt on the phone if shown.
"%HEIST_ADB%" -d install -r "%HEIST_APK%" >>"%HEIST_LOG%" 2>&1
if errorlevel 1 goto failed
echo Launching HEIST...
"%HEIST_ADB%" -d shell am start -W -n io.github.tejjj777.heist.flutter/com.example.heist_flutter.MainActivity >>"%HEIST_LOG%" 2>&1
if errorlevel 1 goto failed
timeout /t 4 /nobreak >nul
"%HEIST_ADB%" -d shell pidof io.github.tejjj777.heist.flutter >>"%HEIST_LOG%" 2>&1
if errorlevel 1 goto failed
>>"%HEIST_LOG%" echo APP_STARTED_AND_RUNNING
type "%HEIST_LOG%"
echo.
echo SUCCESS: HEIST is installed and its process is running on the Moto.
echo Leave this window open and return to ChatGPT for verification.
pause
exit /b 0
:failed
type "%HEIST_LOG%"
echo.
echo HEIST installation or launch did not complete successfully.
echo Leave this error window open and return to ChatGPT.
pause
exit /b 1
