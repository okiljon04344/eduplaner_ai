allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

fun Project.forceJava17() {
    // NOTE: deliberately does NOT use `options.release.set(17)` on JavaCompile
    // tasks — AGP explicitly disallows the `--release` javac flag for tasks
    // compiling against Android APIs (breaks bootclasspath setup, see
    // https://issuetracker.google.com/278800528). sourceCompatibility /
    // targetCompatibility (set via the android extension below) is the
    // AGP-recommended equivalent.

    // Set Java 17 for all Kotlin compile tasks using the new compilerOptions DSL
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    // Also handle the android extension directly if present, using dynamic access
    // to avoid compile-time type errors in the root script.
    if (extensions.findByName("android") != null) {
        val android = extensions.getByName("android")
        try {
            // Attempt to set compileOptions via reflection/dynamic dispatch
            // this covers both BaseExtension and CommonExtension cases.
            val compileOptions = android.javaClass.getMethod("getCompileOptions").invoke(android)
            compileOptions.javaClass.getMethod("setSourceCompatibility", JavaVersion::class.java).invoke(compileOptions, JavaVersion.VERSION_17)
            compileOptions.javaClass.getMethod("setTargetCompatibility", JavaVersion::class.java).invoke(compileOptions, JavaVersion.VERSION_17)
        } catch (e: Exception) {
            // Ignore if the extension doesn't follow the expected structure
        }
    }
}

subprojects {
    // evaluationDependsOn(":app") above can force this project to already be
    // fully evaluated by the time this block runs (":app" is the common
    // case) — afterEvaluate{} throws in that case, so apply directly instead.
    if (state.executed) {
        forceJava17()
    } else {
        afterEvaluate { forceJava17() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
