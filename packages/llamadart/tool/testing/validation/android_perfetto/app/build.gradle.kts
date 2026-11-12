plugins {
    id("com.android.application")
}

android {
    namespace = "dev.llamadart.validation.perfetto"
    compileSdk = 36
    buildToolsVersion = "35.0.0"
    defaultConfig {
        applicationId = "dev.llamadart.validation.perfetto"
        minSdk = 34
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    androidTestImplementation("androidx.test:runner:1.3.0")
    androidTestImplementation("junit:junit:4.12")
    testImplementation("junit:junit:4.12")
}
