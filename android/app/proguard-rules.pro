# FluxDO release shrinking rules.
# Keep this file intentionally small: libraries should ship their own consumer rules.

# Flutter calls plugin/native bridge methods across JNI. Preserve classes containing
# native entry points while allowing the rest of each library to be optimized.
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# Flutter's generated plugin entry point is looked up by the embedding in some
# integration paths; keeping it avoids registration regressions after shrinking.
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Reflection-heavy Android/Flutter plugins commonly rely on these metadata attributes.
# Keeping attributes costs little compared with disabling R8 for the whole APK.
-keepattributes RuntimeVisibleAnnotations,RuntimeInvisibleAnnotations,AnnotationDefault,Signature,InnerClasses,EnclosingMethod
