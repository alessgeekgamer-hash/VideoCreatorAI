@echo off
cd /d "%~dp0"
echo === Video Creator AI - Web (release) ===
flutter pub get
flutter build web --release
echo.
echo Listo: build\web - sirve con: flutter run -d chrome
pause

