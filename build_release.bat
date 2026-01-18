@echo off
echo Building Pomo Time for Play Store release...

echo.
echo Step 1: Cleaning previous builds...
flutter clean

echo.
echo Step 2: Getting dependencies...
flutter pub get

echo.
echo Step 3: Generating launcher icons...
flutter pub run flutter_launcher_icons:main

echo.
echo Step 4: Building release APK...
flutter build apk --release

echo.
echo Step 5: Building release App Bundle (AAB)...
flutter build appbundle --release

echo.
echo Build completed!
echo APK location: build\app\outputs\flutter-apk\app-release.apk
echo AAB location: build\app\outputs\bundle\release\app-release.aab
echo.
echo Upload the AAB file to Play Console for release.
pause