# ─── Règles R8 / ProGuard — Amiin (build release) ────────────────────────────
# Les plugins Flutter fournissent la plupart de leurs règles ; on n'ajoute ici
# que ce qu'ils ne couvrent pas.

# flutter_local_notifications : sérialise les notifications programmées avec
# Gson (réflexion). Sans ces règles, les rappels d'agenda planifiés plantent
# ou disparaissent après redémarrage en release.
-keep class com.dexterous.** { *; }

# Gson — règles officielles (github.com/google/gson, android-proguard-example)
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# Widget d'écran d'accueil : instancié par le système via le manifeste.
-keep class dj.amiin.app.AmiinBriefWidgetProvider { *; }

# Classes Play Core référencées par l'embedding Flutter (deferred components),
# absentes de l'app : évite l'échec R8 « Missing class ».
-dontwarn com.google.android.play.core.**
