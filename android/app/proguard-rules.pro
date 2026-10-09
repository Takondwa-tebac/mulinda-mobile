# Rules for R8 (code shrinking, optimisation and obfuscation) in release builds.
# Flutter's own rules and each plugin's consumer rules are applied automatically;
# these cover plugins that read classes by name at runtime.

# flutter_local_notifications stores scheduled notifications as JSON via Gson.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Background sync (workmanager) starts its worker by class name.
-keep class androidx.work.** { *; }
-keep class dev.fluttercommunity.workmanager.** { *; }
-keep class * extends androidx.work.ListenableWorker { *; }

# SMS capture plugins use reflection / broadcast receivers declared in the manifest.
-keep class com.shounakmulay.telephony.** { *; }
-keep class com.example.flutter_sms_inbox.** { *; }

# Encrypted local database (sqlite3 with ciphers) loads its native library over JNI.
-keep class eu.simonbinder.sqlite3_flutter_libs.** { *; }

# Flutter's optional Play Core (deferred components) is not used.
-dontwarn com.google.android.play.core.**
