// [1. 파일 맨 위에 이 내용을 추가하세요]
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.knue.knuemate" // (본인 앱 이름)
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973" // (아까 설정한 안정적인 버전)

   compileOptions {
        // [기존] isCoreLibraryDesugaringEnabled = true (이건 그대로 두세요)
        isCoreLibraryDesugaringEnabled = true

        // [수정] VERSION_1_8 -> VERSION_17 로 변경
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        // [수정] "1.8" -> "17" 로 변경
        jvmTarget = "17"
    }

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }

    defaultConfig {
        applicationId = "com.knue.knuemate"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

    }
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            // [3. 아까 임시로 debug로 해놨던 걸 release로 바꿉니다!]
            // signingConfig = signingConfigs.getByName("debug")  <-- 이거 지우고 아래 걸로!
            signingConfig = signingConfigs.getByName("release")

            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    
    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
}

dependencies {
    // [여기에 추가하세요]
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    
    implementation(platform("org.jetbrains.kotlin:kotlin-bom:1.8.0"))
}