@echo off
cd /d "%~dp0"
echo === Video Creator AI - APK Android (release) ===
flutter pub get
flutter build apk --release
echo.
echo Listo: build\app\outputs\flutter-apk\app-release.apk
pause

