# Keep Flutter engine & plugin classes intact under R8 shrinking/obfuscation
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep Google Sign-In & Play Services Auth reflection targets
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }
-dontwarn com.google.android.gms.**

# Keep AndroidX / App Links / Image Picker / Share Plus plugin classes
-keep class com.llfbandit.app_links.** { *; }
-keep class dev.fluttercommunity.plus.share.** { *; }
-keep class com.tekartik.sqflite.** { *; }

# Flutter engine optional Play Core deferred-component references (unused in Crease)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
