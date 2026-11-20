plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

group = providers.gradleProperty("GROUP").get()
version = providers.gradleProperty("VERSION_NAME").get()

android {
    namespace = "com.akwelo"
    compileSdk = 35
    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.0")
    // Optional at runtime: only used when AkweloOptions.playIntegrityCloudProjectNumber is set.
    implementation("com.google.android.play:integrity:1.4.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.9.0")

    testImplementation("junit:junit:4.13.2")
    // android.jar stubs org.json in local unit tests; use the real implementation there.
    testImplementation("org.json:json:20240303")
}
