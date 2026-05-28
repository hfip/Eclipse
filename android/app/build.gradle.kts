import java.util.Properties

val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.isFile) {
        localPropertiesFile.inputStream().use { load(it) }
    }
}

fun appleBuildConfigProperties(path: String): List<Pair<String, String>> =
    rootProject.file(path)
        .takeIf { it.isFile }
        ?.readLines()
        ?.mapNotNull { line ->
            val trimmed = line.trim()
            if (trimmed.isBlank() || trimmed.startsWith("//") || !trimmed.contains("=")) {
                null
            } else {
                val name = trimmed.substringBefore("=").trim()
                val value = trimmed.substringAfter("=").substringBefore("//").trim()
                name.takeIf { it.isNotBlank() }?.let { it to value }
            }
        }
        .orEmpty()

val appleBuildConfigProperties: Map<String, String> = listOf(
    "../Build.xcconfig",
    "../Build.local.xcconfig",
)
    .flatMap(::appleBuildConfigProperties)
    .toMap()

fun secretProperty(name: String): String =
    providers.gradleProperty(name)
        .orElse(providers.environmentVariable(name))
        .orElse(localProperties.getProperty(name, ""))
        .get()
        .ifBlank { appleBuildConfigProperties[name].orEmpty() }

fun buildConfigString(value: String): String =
    "\"${value.replace("\\", "\\\\").replace("\"", "\\\"")}\""

val tmdbApiKey = secretProperty("TMDB_API_KEY")
val anilistClientId = secretProperty("ANILIST_CLIENT_ID")
val anilistClientSecret = secretProperty("ANILIST_CLIENT_SECRET")
val traktClientId = secretProperty("TRAKT_CLIENT_ID")
val traktClientSecret = secretProperty("TRAKT_CLIENT_SECRET")
val malClientId = secretProperty("MAL_CLIENT_ID")
val malClientSecret = secretProperty("MAL_CLIENT_SECRET")

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "dev.soupy.eclipse.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "dev.soupy.eclipse.android"
        minSdk = 26
        targetSdk = 36
        versionCode = 4
        versionName = "1.0.4"
        buildConfigField("String", "TMDB_API_KEY", buildConfigString(tmdbApiKey))
        buildConfigField("String", "ANILIST_CLIENT_ID", buildConfigString(anilistClientId))
        buildConfigField("String", "ANILIST_CLIENT_SECRET", buildConfigString(anilistClientSecret))
        buildConfigField("String", "TRAKT_CLIENT_ID", buildConfigString(traktClientId))
        buildConfigField("String", "TRAKT_CLIENT_SECRET", buildConfigString(traktClientSecret))
        buildConfigField("String", "MAL_CLIENT_ID", buildConfigString(malClientId))
        buildConfigField("String", "MAL_CLIENT_SECRET", buildConfigString(malClientSecret))

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables.useSupportLibrary = true
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

dependencies {
    implementation(project(":core:design"))
    implementation(project(":core:model"))
    implementation(project(":core:network"))
    implementation(project(":core:storage"))
    implementation(project(":core:player"))
    implementation(project(":core:js"))
    implementation(project(":feature:home"))
    implementation(project(":feature:search"))
    implementation(project(":feature:detail"))
    implementation(project(":feature:schedule"))
    implementation(project(":feature:services"))
    implementation(project(":feature:library"))
    implementation(project(":feature:downloads"))
    implementation(project(":feature:settings"))
    implementation(project(":feature:manga"))
    implementation(project(":feature:novel"))

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.foundation)
    implementation(libs.androidx.compose.material.icons)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.viewmodel.ktx)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.work.runtime.ktx)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)

    debugImplementation(libs.androidx.compose.ui.tooling)
    testImplementation(libs.kotlin.test.junit)
}

