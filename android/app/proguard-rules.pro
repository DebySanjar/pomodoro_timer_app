# Flutter specific rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Hive database
-keep class hive.** { *; }
-keep class * extends hive.HiveObject { *; }

# Audio players
-keep class com.ryanheise.audioservice.** { *; }
-keep class com.ryanheise.audio_session.** { *; }

# Local notifications
-keep class com.dexterous.** { *; }

# Vibration
-keep class io.flutter.plugins.vibration.** { *; }

# Wakelock
-keep class creativemaybeno.wakelock.** { *; }

# Device info
-keep class io.flutter.plugins.deviceinfo.** { *; }

# Shared preferences
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Don't obfuscate
-dontobfuscate