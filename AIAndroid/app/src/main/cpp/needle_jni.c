/* JNI bridge to the Cactus Needle 3 C API for NeedleEmbedder.kt.
 *
 * The needle API is one process-global model and is NOT thread-safe;
 * NeedleEmbedder.kt serializes every call through a single-thread executor.
 * needle_jni_stub.c implements the identical surface for ABIs without a
 * vendored engine. Design: docs/ROUTING.md §4. */
#include <jni.h>
#include <string.h>
#include "needle.h"

#define JNI(name) Java_ai_ecoinference_app_router_NeedleEmbedder_##name

/* Loads the weights and initializes the engine. Returns the embedding
 * dimension on success, negative on failure (nativeLastError has detail). */
JNIEXPORT jint JNICALL JNI(nativeLoad)(JNIEnv *env, jclass clazz, jbyteArray cact) {
    (void)clazz;
    jsize n = (*env)->GetArrayLength(env, cact);
    jbyte *buf = (*env)->GetByteArrayElements(env, cact, NULL);
    if (!buf) return -1;
    int r = needle_load((const unsigned char *)buf, (unsigned long long)n);
    (*env)->ReleaseByteArrayElements(env, cact, buf, JNI_ABORT);
    if (r < 0) return r;

    /* Same two-step init as the probe harness (embedder.c): empty system
     * prompt first, fall back to a minimal one for builds that reject it. */
    if (needle_init("", "[]", NULL) < 0) {
        if (needle_init("You are an embedding engine.", "[]", NULL) < 0) return -2;
    }
    int dim = needle_embed("dim?", NULL, 0);
    return dim > 0 ? dim : -3;
}

/* Embeds one text into out (capacity floats). Returns needle_embed's result:
 * 0 on success, negative on failure. */
JNIEXPORT jint JNICALL JNI(nativeEmbed)(JNIEnv *env, jclass clazz, jstring text, jfloatArray out) {
    (void)clazz;
    const char *s = (*env)->GetStringUTFChars(env, text, NULL);
    if (!s) return -1;
    jsize cap = (*env)->GetArrayLength(env, out);
    jfloat *o = (*env)->GetFloatArrayElements(env, out, NULL);
    if (!o) { (*env)->ReleaseStringUTFChars(env, text, s); return -1; }
    int r = needle_embed(s, (float *)o, (int)cap);
    (*env)->ReleaseFloatArrayElements(env, out, o, 0);
    (*env)->ReleaseStringUTFChars(env, text, s);
    return r;
}

JNIEXPORT jstring JNICALL JNI(nativeLastError)(JNIEnv *env, jclass clazz) {
    (void)clazz;
    const char *e = needle_last_error();
    return (*env)->NewStringUTF(env, e ? e : "");
}

JNIEXPORT void JNICALL JNI(nativeReset)(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    needle_reset();
}
