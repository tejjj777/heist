@echo off
setlocal
for %%I in ("%~dp0..\..\..\sdk\android\platform-tools\adb.exe") do set "HEIST_ADB=%%~fI"
if not exist "%HEIST_ADB%" (
  echo Flutter workspace Android platform-tools were not found.
  pause
  exit /b 1
)
echo Starting the official Android Debug Bridge under your Windows account.
echo Android will save this computer's debugging keys in your .android folder.
"%HEIST_ADB%" start-server
if errorlevel 1 (
  echo ADB could not start. Leave this window open so the error can be reviewed.
  pause
  exit /b 1
)
echo Unlock your phone and approve Allow USB debugging if Android asks.
"%HEIST_ADB%" devices -l
echo Return to ChatGPT when this window shows the connected phone.
pause
