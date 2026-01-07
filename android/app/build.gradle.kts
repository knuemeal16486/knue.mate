plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flutter_application_1" // (본인 앱 이름)
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
        applicationId = "com.example.flutter_application_1" // (본인 ID)
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // [기존 코드] 리소스 축소 끄기 (아까 설정한 것)
            isMinifyEnabled = false
            isShrinkResources = false
            
            // [★ 이 줄을 꼭 추가하세요! ★] 
            // 배포용 빌드에도 임시로 'debug' 서명을 사용한다는 뜻입니다.
            signingConfig = signingConfigs.getByName("debug")

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