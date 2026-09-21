/* Stub JNI for ABIs without a vendored Needle engine (x86_64 emulators, or a
 * checkout where fetch_needle.sh hasn't run). Same surface as needle_jni.c;
 * nativeLoad reports unavailable so NeedleEmbedder.kt fails open to keyword
 * facts and routing keeps working. */
#include <jni.h>

#define JNI(name) Java_ai_ecoinference_app_router_NeedleEmbedder_##name

JNIEXPORT jint JNICALL JNI(nativeLoad)(JNIEnv *env, jclass clazz, jbyteArray cact) {
    (void)env; (void)clazz; (void)cact;
    return -100;
}

JNIEXPORT jint JNICALL JNI(nativeEmbed)(JNIEnv *env, jclass clazz, jstring text, jfloatArray out) {
    (void)env; (void)clazz; (void)text; (void)out;
    return -100;
}

JNIEXPORT jstring JNICALL JNI(nativeLastError)(JNIEnv *env, jclass clazz) {
    (void)clazz;
    return (*env)->NewStringUTF(env, "needle engine not vendored for this ABI (run fetch_needle.sh)");
}

JNIEXPORT void JNICALL JNI(nativeReset)(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
}
