import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Clé de signature release : android/key.properties (jamais commité, cf.
// android/.gitignore). Contenu attendu :
//   storePassword=…  keyPassword=…  keyAlias=upload  storeFile=/chemin/upload-keystore.jks
//
// Sans ce fichier, un build release ÉCHOUE (plus de repli silencieux sur la
// clé debug, qui produisait un APK non publiable et non mettable à jour).
// Pour un test local ponctuel signé debug, exporter AMIIN_ALLOW_DEBUG_SIGNING=1.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) load(FileInputStream(keystorePropertiesFile))
}
val allowDebugSigning = System.getenv("AMIIN_ALLOW_DEBUG_SIGNING") == "1"
val isReleaseBuild = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
if (isReleaseBuild && !keystorePropertiesFile.exists() && !allowDebugSigning) {
    throw GradleException(
        "Build release impossible : android/key.properties introuvable. " +
        "Créer la clé d'upload (voir android/app/build.gradle.kts) ou, pour un " +
        "test local uniquement, exporter AMIIN_ALLOW_DEBUG_SIGNING=1."
    )
}

android {
    namespace = "dj.amiin.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Identifiant définitif sur le Play Store : NE PLUS LE CHANGER après la
        // première publication (un autre identifiant = une autre application).
        applicationId = "dj.amiin.app"
        minSdk = flutter.minSdkVersion
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
            signingConfig = if (keystorePropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")   // uniquement avec AMIIN_ALLOW_DEBUG_SIGNING=1
            // R8 : réduction + obfuscation du code Java/Kotlin et suppression
            // des ressources inutilisées. (Le code Dart est obfusqué à part :
            // --obfuscate --split-debug-info, cf. tool/build_release.sh.)
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Play Integrity : preuve que la requête vient de l'app officielle (MainActivity.kt)
    implementation("com.google.android.play:integrity:1.6.0")
}
