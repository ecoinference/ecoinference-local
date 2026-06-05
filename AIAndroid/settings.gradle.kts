pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()   // Chaquopy 13+ is published here
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "AIAndroid"
include(":app")
