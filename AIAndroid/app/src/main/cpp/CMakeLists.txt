# JNI wrapper around the Cactus Needle 3 C API (vendored by fetch_needle.sh
# into cpp/needle/<ABI>/ — never committed, same policy as AIiOS/Frameworks/).
#
# ABIs without a vendored libneedle.a (e.g. x86_64 emulator builds) compile
# needle_jni_stub.c instead: identical JNI surface, nativeLoad reports the
# engine as unavailable, and NeedleEmbedder.kt fails open to keyword facts.
cmake_minimum_required(VERSION 3.22.1)
# CXX must be enabled even though our sources are C: the NDK toolchain only
# links the STL (c++_static, set from Gradle) into targets that contain C++
# sources, and libneedle.a is a C++ archive. needle_stl_anchor.cpp is that
# one translation unit.
project(needlejni C CXX)

set(NEEDLE_PREBUILT_DIR ${CMAKE_CURRENT_SOURCE_DIR}/needle/${ANDROID_ABI})

add_library(needlejni SHARED)

if(EXISTS ${NEEDLE_PREBUILT_DIR}/libneedle.a)
    add_library(needle_prebuilt STATIC IMPORTED)
    set_target_properties(needle_prebuilt PROPERTIES
        IMPORTED_LOCATION ${NEEDLE_PREBUILT_DIR}/libneedle.a)
    target_sources(needlejni PRIVATE needle_jni.c needle_stl_anchor.cpp)
    target_include_directories(needlejni PRIVATE ${NEEDLE_PREBUILT_DIR})
    # libneedle.a is C++ internally — the c++_static STL is set from Gradle.
    target_link_libraries(needlejni needle_prebuilt log)
    message(STATUS "needlejni: real engine for ${ANDROID_ABI}")
else()
    target_sources(needlejni PRIVATE needle_jni_stub.c)
    target_link_libraries(needlejni log)
    message(STATUS "needlejni: STUB for ${ANDROID_ABI} (no vendored libneedle.a — run fetch_needle.sh)")
endif()
