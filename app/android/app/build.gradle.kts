import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.alqadisiyah.qadisiyah"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.alqadisiyah.qadisiyah"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // مفتاح ثابت لنسخ التجربة (Debug) محفوظ في المستودع، حتى يُثبَّت كل APK
        // تجريبي جديد فوق السابق دون حذف التطبيق أو بياناته. نسخ Debug قابلة
        // للفحص بطبيعتها ولا تُستخدم إلا ببيانات تجريبية.
        // لا يُغيَّر هذا المفتاح أبدًا: تغييره يمنع التحديث فوق النسخ المثبتة.
        getByName("debug") {
            storeFile = rootProject.file("trial-debug.keystore")
            storePassword = "android"
            keyAlias = "qadisiyah-trial"
            keyPassword = "android"
        }
    }

    // مفتاح الإصدار للتوزيع يُقرأ من android/key.properties (غير مرفوع للمستودع)
    // ولا يُستبدل بمفتاح التجربة إطلاقًا؛ بدونه تُبنى نسخة الإصدار غير موقعة.
    val keystoreFile = rootProject.file("key.properties")
    val releaseSigning = if (keystoreFile.exists()) {
        val props = Properties().apply { keystoreFile.inputStream().use { load(it) } }
        signingConfigs.create("release") {
            storeFile = file(props.getProperty("storeFile"))
            storePassword = props.getProperty("storePassword")
            keyAlias = props.getProperty("keyAlias")
            keyPassword = props.getProperty("keyPassword")
        }
    } else {
        null
    }

    buildTypes {
        release {
            signingConfig = releaseSigning
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
