import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("app/key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.jahanbit.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.jahanbit.app"
        // حداقل SDK برای flutter_inappwebview و الزامات فروشگاه
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // بدون key.properties بیلد release امضا نمی‌شود تا اشتباهاً debug آپلود نشود.
                throw GradleException(
                    "Missing android/app/key.properties. Copy key.properties.example and configure the upload keystore before releasing.",
                )
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // فرمت خروجی: Jahan_Bit-v1.0.0(1)-release.apk
    applicationVariants.all {
        val variant = this
        val appName = "Jahan_Bit"
        val versionName = variant.versionName
        val versionCode = variant.versionCode
        val buildType = variant.buildType.name

        variant.outputs.all {
            val outputFileName = "${appName}-v${versionName}(${versionCode})-${buildType}.apk"
            (this as com.android.build.gradle.internal.api.BaseVariantOutputImpl).outputFileName = outputFileName
        }
    }
}

flutter {
    source = "../.."
}
