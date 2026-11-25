# Classes chamadas só pelo código nativo (JNI) dos plugins; o R8 não enxerga
# esse uso e as removia do APK de release (ClassNotFoundException PathUtils).
-keep class io.flutter.util.PathUtils { *; }
-keep class com.github.dart_lang.jni.** { *; }
-keep class com.github.dart_lang.jni_flutter.** { *; }
