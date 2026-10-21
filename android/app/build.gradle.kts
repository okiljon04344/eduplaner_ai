import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // android.newDsl / android.builtInKotlin are set to false in
    // gradle.properties (AGP 9's new DSL crashes the Flutter Gradle plugin
    // on this Flutter version) — so the explicit Kotlin plugin is required.
    id("org.jetbrains.kotlin.android")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.eduplanner.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    defaultConfig {
        applicationId = "com.eduplanner.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Debug-key fallback only for local release testing
            // (ALLOW_DEBUG_SIGNING=true); otherwise key.properties is required.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

// Never ship a release build signed with the debug key by accident.
gradle.taskGraph.whenReady {
    val releaseRequested = allTasks.any { it.name.contains("Release", ignoreCase = false) }
    if (releaseRequested && !keystorePropertiesFile.exists() && System.getenv("ALLOW_DEBUG_SIGNING") != "true") {
        throw GradleException(
            "Release build requires android/key.properties (storeFile, storePassword, keyAlias, keyPassword) " +
                "pointing at the upload keystore. For local release testing only, set ALLOW_DEBUG_SIGNING=true."
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// NOTE: no `options.release.set(17)` here — AGP disallows the `--release`
// javac flag for tasks compiling against Android APIs (breaks bootclasspath
// setup, see https://issuetracker.google.com/278800528). `compileOptions`
// above (sourceCompatibility/targetCompatibility) is the correct mechanism.

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
