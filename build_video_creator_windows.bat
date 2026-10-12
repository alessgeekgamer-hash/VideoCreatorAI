@echo off
set "PATH=%~dp0nuget_tool;%PATH%"
cd /d "%~dp0"
echo === Video Creator AI - EXE Windows (release) ===
flutter pub get
flutter build windows --release
echo.
echo Listo: build\windows\x64\runner\Release\video_creator_ai.exe
pause


