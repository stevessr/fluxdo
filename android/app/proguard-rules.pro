# Flutter 自动生成的混淆规则已由 Flutter Gradle Plugin 注入
# 本文件用于项目特定的保留规则

# 保留 Firebase Crashlytics 堆栈跟踪（调试崩溃必需）
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# 保留 Discourse API 模型的字段名（JSON 序列化）
-keepclassmembers class com.github.lingyan000.fluxdo.** {
    @com.google.gson.annotations.SerializedName <fields>;
}

# 保留原生方法（JNI / Rust FFI）
-keepclasseswithmembernames class * {
    native <methods>;
}

# 保留 WebView JavaScript 接口
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Cronet 保留规则
-keep class org.chromium.net.** { *; }
-dontwarn org.chromium.net.**

# 移除日志调用（Release 不需要）
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}
