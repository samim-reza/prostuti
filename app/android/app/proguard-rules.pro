# ---------------------------------------------------------------------------
# Prostuti release (R8) keep rules.
# Flutter and most plugins ship their own rules; these cover reflection that
# R8 full mode cannot see.
# ---------------------------------------------------------------------------

# Room databases (WorkManager's WorkDatabase among them) are created with
# Class.forName("<Name>_Impl").newInstance(): keep the generated classes and
# their no-arg constructors.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }

# WorkManager instantiates workers and input mergers by class name.
-keep class * extends androidx.work.ListenableWorker { <init>(android.content.Context, androidx.work.WorkerParameters); }
-keep class * extends androidx.work.InputMerger { <init>(); }

# Gson (flutter_local_notifications persists scheduled notifications with it).
-keepattributes Signature, *Annotation*, EnclosingMethod, InnerClasses
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.dexterous.flutterlocalnotifications.** { *; }
