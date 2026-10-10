# FPL Arabia — Flutter starter

## Important
This is a starter source project. It needs to be opened/imported in a Flutter project in Klencod IDE. If Klencod already creates the Android folder, copy `lib/main.dart` and merge the permissions/receivers from `android/app/src/main/AndroidManifest.xml` into its existing manifest rather than blindly replacing generated files.

## Steps
1. Create a new Flutter project in Klencod named `fpl_arabia`.
2. Replace `lib/main.dart` with the supplied file.
3. Replace or update `pubspec.yaml` with the supplied file.
4. In the Android manifest, ensure INTERNET and POST_NOTIFICATIONS permissions are present; scheduled-notification receiver entries are included in this sample manifest.
5. Run `flutter pub get`.
6. Run `flutter build apk --release`.
7. APK output: `build/app/outputs/flutter-apk/app-release.apk`.

The public FPL API is not an official documented developer API and can change or block requests. Notifications in this starter are a one-minute test reminder; deadline-based notifications and a full legal 15-player/£100m squad validator can be added after confirming the first build works.
