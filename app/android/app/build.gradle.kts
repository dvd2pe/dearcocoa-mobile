import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    fun loadKeystoreProperties(fileName: String): Pair<Properties, Boolean> {
        val properties = Properties()
        val propertiesFile = rootProject.file(fileName)
        if (propertiesFile.exists()) {
            properties.load(FileInputStream(propertiesFile))
        }

        val hasRequiredProperties = propertiesFile.exists() &&
            properties["keyAlias"] != null &&
            properties["keyPassword"] != null &&
            properties["storeFile"] != null &&
            properties["storePassword"] != null
        return properties to hasRequiredProperties
    }

    val (globalKeystoreProperties, hasGlobalKeystore) =
        loadKeystoreProperties("key-global.properties")
    val (cnKeystoreProperties, hasCnKeystore) =
        loadKeystoreProperties("key-cn.properties")
    val (earlyKeystoreProperties, hasEarlyKeystore) =
        loadKeystoreProperties("key-early.properties")

    namespace = "app.dearcocoa.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.3.13750724"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // richiesto da flutter_local_notifications (check AAR metadata)
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "app.dearcocoa.mobile"
        minSdk = 26  // Required by health plugin 13.2.1
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasGlobalKeystore) {
            create("globalRelease") {
                keyAlias = globalKeystoreProperties["keyAlias"] as String
                keyPassword = globalKeystoreProperties["keyPassword"] as String
                storeFile = file(globalKeystoreProperties["storeFile"] as String)
                storePassword = globalKeystoreProperties["storePassword"] as String
            }
        }
        if (hasCnKeystore) {
            create("cnRelease") {
                keyAlias = cnKeystoreProperties["keyAlias"] as String
                keyPassword = cnKeystoreProperties["keyPassword"] as String
                storeFile = file(cnKeystoreProperties["storeFile"] as String)
                storePassword = cnKeystoreProperties["storePassword"] as String
            }
        }
        if (hasEarlyKeystore) {
            create("earlyRelease") {
                keyAlias = earlyKeystoreProperties["keyAlias"] as String
                keyPassword = earlyKeystoreProperties["keyPassword"] as String
                storeFile = file(earlyKeystoreProperties["storeFile"] as String)
                storePassword = earlyKeystoreProperties["storePassword"] as String
            }
        }
    }

    val globalApplicationId = "app.dearcocoa.mobile"
    val cnApplicationId = "app.dearcocoa.mobile.cn"
    val globalEarlyApplicationId = "app.dearcocoa.mobile.early"
    val cnEarlyApplicationId = "app.dearcocoa.mobile.cn.early"
    val globalDevApplicationId = "app.dearcocoa.mobile.dev"
    val cnDevApplicationId = "app.dearcocoa.mobile.cn.dev"

    // Static shortcut targetPackage must be a literal in each flavor overlay.
    // Android persists @string references as resource IDs in ShortcutInfo intents.
    flavorDimensions += "market"
    productFlavors {
        create("global") {
            dimension = "market"
            applicationId = globalApplicationId
            manifestPlaceholders["appLabel"] = "DearCocoa"
            if (hasGlobalKeystore) {
                signingConfig = signingConfigs.getByName("globalRelease")
            }
        }
        create("cn") {
            dimension = "market"
            applicationId = cnApplicationId
            manifestPlaceholders["appLabel"] = "DearCocoa"
            if (hasCnKeystore) {
                signingConfig = signingConfigs.getByName("cnRelease")
            }
        }
        create("globalEarly") {
            dimension = "market"
            applicationId = globalEarlyApplicationId
            manifestPlaceholders["appLabel"] = "Memex Early"
            if (hasEarlyKeystore) {
                signingConfig = signingConfigs.getByName("earlyRelease")
            }
        }
        create("cnEarly") {
            dimension = "market"
            applicationId = cnEarlyApplicationId
            manifestPlaceholders["appLabel"] = "Memex Early CN"
            if (hasEarlyKeystore) {
                signingConfig = signingConfigs.getByName("earlyRelease")
            }
        }
        create("globalDev") {
            dimension = "market"
            applicationId = globalDevApplicationId
            manifestPlaceholders["appLabel"] = "DearCocoa Dev"
        }
        create("cnDev") {
            dimension = "market"
            applicationId = cnDevApplicationId
            manifestPlaceholders["appLabel"] = "Memex Dev CN"
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    applicationVariants.all {
        val variant = this
        outputs.all {
            val output = this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
            // split-per-abi: each split has its own ABI filter; the fat APK has none.
            // Without the ABI suffix all splits would race on the same output file name.
            val abi = output.getFilter(com.android.build.OutputFile.ABI)
            val abiSuffix = if (abi != null) "_$abi" else ""
            output.outputFileName = "dearcocoa_${variant.flavorName}_${variant.versionName}_${variant.versionCode}$abiSuffix.apk"
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.work:work-runtime:2.10.2")
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
}
