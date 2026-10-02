# Reglas minimas para que flutter_local_notifications sobreviva R8/minify
# en release. Sin esto, el plugin puede funcionar "a medias": la
# notificacion inmediata anda bien, pero la reprogramacion tras reiniciar
# el telefono se rompe en silencio (solo se nota probando release de
# verdad, nunca en debug, porque debug no minifica).

# El plugin expone dos receivers (los declarados en AndroidManifest.xml:
# ScheduledNotificationBootReceiver y ScheduledNotificationReceiver) que
# Android instancia por nombre de clase via reflexion, no por una llamada
# directa desde nuestro codigo. R8 no tiene forma de saber que esas
# clases "se usan" si no se le dice explicitamente, y podria eliminarlas
# o renombrarlas por considerarlas codigo muerto.
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# El plugin usa Gson internamente para serializar los datos de cada
# notificacion programada (fecha, hora, canal, etc.) y guardarlos en
# SharedPreferences, para poder reprogramarlos cuando el receiver de
# arriba se dispara tras un reinicio. Gson deserializa usando reflexion
# sobre la firma generica (Signature) de los tipos; sin conservar esos
# atributos, la deserializacion falla silenciosamente en release y las
# notificaciones agendadas se pierden al reiniciar el telefono.
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-dontwarn com.google.gson.**
