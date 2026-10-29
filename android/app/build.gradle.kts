import java.net.URI
import java.security.KeyStore
import java.security.PrivateKey
import java.security.cert.X509Certificate
import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val uploadVariableNames = listOf(
    "ANDROID_UPLOAD_STORE_FILE",
    "ANDROID_UPLOAD_STORE_PASSWORD",
    "ANDROID_UPLOAD_KEY_ALIAS",
    "ANDROID_UPLOAD_KEY_PASSWORD",
)
val uploadSettings = uploadVariableNames.associateWith {
    providers.environmentVariable(it).orNull?.takeIf(String::isNotBlank)
}
val mobileDirectory = projectDir.parentFile.parentFile

// Validate only tasks that actually build release, so debug needs no upload key.
gradle.taskGraph.whenReady {
    val appTasks = allTasks.filter { it.project.path == project.path }
    val releaseBuild = appTasks.any { it.name.contains("Release", ignoreCase = true) }
    if (releaseBuild) {
        val missing = uploadVariableNames.filter { uploadSettings[it] == null }
        if (missing.isNotEmpty()) {
            throw GradleException(
                "Missing release signing configuration. Set ANDROID_UPLOAD_* environment variables: " +
                    missing.joinToString(", "),
            )
        }
        val uploadFile = file(uploadSettings.getValue("ANDROID_UPLOAD_STORE_FILE")!!).canonicalFile
        val repositoryDirectory = mobileDirectory.parentFile.parentFile.canonicalFile
        if (!uploadFile.isFile || !uploadFile.canRead()) {
            throw GradleException("Upload keystore is not readable. Check ANDROID_UPLOAD_STORE_FILE.")
        }
        if (uploadFile.toPath().startsWith(repositoryDirectory.toPath())) {
            throw GradleException("Store the upload keystore outside the repository.")
        }
        val alias = uploadSettings.getValue("ANDROID_UPLOAD_KEY_ALIAS")!!
        val certificate = try {
            val store = KeyStore.getInstance(
                uploadFile,
                uploadSettings.getValue("ANDROID_UPLOAD_STORE_PASSWORD")!!.toCharArray(),
            )
            if (store.getKey(alias, uploadSettings.getValue("ANDROID_UPLOAD_KEY_PASSWORD")!!.toCharArray())
                !is PrivateKey) {
                throw IllegalArgumentException()
            }
            store.getCertificate(alias) as X509Certificate
        } catch (_: Exception) {
            throw GradleException("Cannot open the upload key. Check ANDROID_UPLOAD_* configuration.")
        }
        val subject = certificate.subjectX500Principal.name.replace(" ", "").lowercase()
        if (alias.equals("androiddebugkey", ignoreCase = true) || subject.contains("cn=androiddebug")) {
            throw GradleException("Android Debug certificates cannot sign release builds.")
        }
    }

    if (appTasks.any { it.name.startsWith("compileFlutterBuild") }) {
        // Dart defines are extractable client configuration, never secret storage.
        val frameworkNames = setOf(
            "FLUTTER_BUILD_NAME", "FLUTTER_BUILD_NUMBER", "FLUTTER_VERSION", "FLUTTER_CHANNEL",
            "FLUTTER_GIT_URL", "FLUTTER_FRAMEWORK_REVISION", "FLUTTER_ENGINE_REVISION",
            "FLUTTER_DART_VERSION",
        )
        val defines = try {
            (findProperty("dart-defines") as? String).orEmpty().split(",")
                .filter(String::isNotBlank).map {
                    String(Base64.getDecoder().decode(it), Charsets.UTF_8)
                }.associate { it.substringBefore("=") to it.substringAfter("=", "") }
        } catch (_: Exception) {
            throw GradleException("Invalid public Dart define encoding.")
        }
        // SDK instrumentation controls are public and accepted only for debug
        // test targets. Release/ordinary builds retain the config allowlist.
        val target = (findProperty("target") as? String).orEmpty().replace('\\', '/')
        val instrumentedDebug = !releaseBuild &&
            (target.endsWith("/integration_test/full_system_test.dart") ||
             target.endsWith("/integration_test/gemini_canary_test.dart") ||
             target.endsWith("/integration_test/permission_allow_test.dart") ||
             target.endsWith("/integration_test/production_safe_test.dart") ||
             (target.contains("flutter_test_listener.") && target.endsWith("/listener.dart")))
        val instrumentationNames = if (instrumentedDebug) setOf(
            "E2E_RUN_ID", "E2E_CONTROL_URL", "E2E_PRODUCTION_SAFE", "E2E_EXPECTED_REVISION", "E2E_REAL_PAYOS", "E2E_PAYOS_PLAN", "INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE",
        ) else emptySet()
        if (defines["E2E_RUN_ID"] != null && !Regex("^homemind-e2e-[a-f0-9]{12}$").matches(defines.getValue("E2E_RUN_ID"))) {
            throw GradleException("Invalid public fixture ownership identifier.")
        }
        if (defines["INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE"] != null &&
            defines["INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE"] !in setOf("true", "false")) {
            throw GradleException("Invalid SDK instrumentation boolean.")
        }
        if (defines["E2E_PRODUCTION_SAFE"] != null && defines["E2E_PRODUCTION_SAFE"] !in setOf("true", "false")) {
            throw GradleException("Invalid production-safe instrumentation boolean.")
        }
        if (defines["E2E_REAL_PAYOS"] != null && defines["E2E_REAL_PAYOS"] != "true") {
            throw GradleException("Real-payOS instrumentation requires an explicit true value.")
        }
        if ((defines["E2E_REAL_PAYOS"] != null) != (defines["E2E_PAYOS_PLAN"] != null) ||
            (defines["E2E_PAYOS_PLAN"] != null && defines["E2E_PAYOS_PLAN"] !in setOf("personal", "family", "micro_pos"))) {
            throw GradleException("Real-payOS instrumentation requires one approved plan.")
        }
        if (defines["E2E_EXPECTED_REVISION"] != null && !Regex("^[a-f0-9]{40}$").matches(defines.getValue("E2E_EXPECTED_REVISION"))) {
            throw GradleException("Invalid public expected revision.")
        }
        if (defines["E2E_CONTROL_URL"] != null) {
            val control = try { URI(defines.getValue("E2E_CONTROL_URL")) } catch (_: Exception) { null }
            if (control == null || control.scheme != "http" || control.host != "127.0.0.1" || control.port < 1 || control.userInfo != null || control.rawQuery != null || control.rawFragment != null || control.path != "/" + defines["E2E_RUN_ID"]) {
                throw GradleException("Native host controls require a public owned loopback endpoint.")
            }
        }
        val unsupported = defines.keys - frameworkNames - setOf("BACKEND_BASE_URL", "APP_DISTRIBUTION") - instrumentationNames
        if (unsupported.isNotEmpty()) {
            throw GradleException("Only public BACKEND_BASE_URL and APP_DISTRIBUTION are supported as application Dart config.")
        }
        if (defines["APP_DISTRIBUTION"] != null && defines["APP_DISTRIBUTION"] !in setOf("store", "direct")) {
            throw GradleException("APP_DISTRIBUTION must be store or direct.")
        }
        val backend = try { URI(defines["BACKEND_BASE_URL"].orEmpty()) } catch (_: Exception) { null }
        if (backend == null || backend.host.isNullOrEmpty() || backend.scheme !in setOf("http", "https") ||
            backend.userInfo != null || backend.rawQuery != null || backend.rawFragment != null) {
            throw GradleException("Pass a public BACKEND_BASE_URL via --dart-define or config/development.json.")
        }
        if (releaseBuild && backend.scheme != "https") {
            throw GradleException("Release BACKEND_BASE_URL must use HTTPS.")
        }
        val pubspec = mobileDirectory.resolve("pubspec.yaml").readText()
        val envAsset = Regex(
            """(?m)^\s*-\s*["']?(?:[^\s"']*/)?\.env(?:\.[\w.-]+)?["']?\s*(?:#.*)?$""",
            RegexOption.IGNORE_CASE,
        )
        if (envAsset.containsMatchIn(pubspec)) {
            throw GradleException("Do not bundle .env files as Flutter assets; use public Dart defines.")
        }
        val privatePattern = Regex(
            """AIza[0-9A-Za-z_-]{35}|sk-[0-9A-Za-z_-]{20,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?)://[^/\s]+:[^@\s]+@""",
        )
        for (sourceRoot in listOf("lib", "assets", "android/app/src")) {
            for (source in fileTree(mobileDirectory.resolve(sourceRoot))) {
                if (source.name.equals(".env", ignoreCase = true) || source.name.lowercase().startsWith(".env.")) {
                    throw GradleException("Environment files cannot be included in mobile source/assets.")
                }
                if (privatePattern.containsMatchIn(source.readBytes().toString(Charsets.ISO_8859_1))) {
                    throw GradleException("A private credential pattern was found in mobile source/assets. Remove it before building.")
                }
            }
        }
    }
}

android {
    namespace = "vn.homemind.homemind_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "vn.homemind.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("upload") {
            uploadSettings["ANDROID_UPLOAD_STORE_FILE"]?.let { storeFile = file(it) }
            storePassword = uploadSettings["ANDROID_UPLOAD_STORE_PASSWORD"]
            keyAlias = uploadSettings["ANDROID_UPLOAD_KEY_ALIAS"]
            keyPassword = uploadSettings["ANDROID_UPLOAD_KEY_PASSWORD"]
        }
    }

    buildTypes {
        release {
            isDebuggable = false
            signingConfig = signingConfigs.getByName("upload")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
