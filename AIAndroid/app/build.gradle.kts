plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.chaquopy)
    alias(libs.plugins.google.services)
}

android {
    namespace  = "ai.ecoinference.app"
    compileSdk = 35

    defaultConfig {
        // Matches iOS bundle ID (ai.ecoinference.eiapp) so both platforms share
        // one identifier. namespace stays "ai.ecoinference.app" deliberately —
        // it only affects generated R/BuildConfig class packages, not the
        // installed app ID, so no Kotlin source files need to change.
        applicationId = "ai.ecoinference.eiapp"
        minSdk        = 26        // LiteRT-LM requires API 26+
        targetSdk     = 35
        versionCode   = 1
        versionName   = "1.0.0"

        // Chaquopy requires explicit ABI list.
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    buildFeatures {
        compose      = true
        buildConfig  = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        }
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    testOptions {
        unitTests {
            // android.util.Log (and other stubbed Android SDK calls) throw by
            // default on the plain JVM test runner ("not mocked") — return
            // defaults instead so logic tests that happen to log don't crash.
            isReturnDefaultValues = true
        }
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.coroutines.play.services)
    implementation(libs.kotlinx.serialization.json)

    // Compose
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.extended)
    debugImplementation(libs.compose.ui.tooling)

    // Lifecycle / ViewModel
    implementation(libs.lifecycle.viewmodel.ktx)
    implementation(libs.lifecycle.viewmodel.compose)
    implementation(libs.lifecycle.runtime.compose)
    implementation(libs.activity.compose)

    // Image loading
    implementation(libs.coil.compose)

    // Runtime permissions
    implementation(libs.accompanist.permissions)

    // Location
    implementation(libs.play.services.location)

    // Downloads
    implementation(libs.okhttp)

    // Math & signal processing (stats, FFT, regression) — no network calls
    implementation(libs.commons.math)

    // On-device inference — LiteRT-LM (.litertlm bundle support)
    implementation(libs.litertlm.android)

    // Settings persistence
    implementation(libs.datastore.preferences)

    // Firebase — Auth, Firestore, Storage (mirrors iOS GoogleService-Info.plist setup)
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.auth)
    implementation(libs.firebase.firestore)
    implementation(libs.firebase.storage)
    implementation(libs.firebase.config)

    // Unit tests (local JVM, no device/emulator needed)
    testImplementation(libs.junit)
}

// ── Chaquopy — on-device Python runtime ───────────────────────────────────────
chaquopy {
    defaultConfig {
        version = "3.10"
        pip {
            // Scientific / numeric
            install("numpy")
            install("pandas")
            install("scipy")
            install("matplotlib")
            // Data viz (pure Python — no native wheel needed)
            install("plotly")
            // Geo / astronomy (pure Python)
            install("astral")
            install("folium")
            install("shapely")
            // QR code generation (pure Python, uses Pillow)
            install("qrcode")
            // Symbolic mathematics (pure Python)
            install("sympy")
        }
    }
}
