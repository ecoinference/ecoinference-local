package ai.ecoinference.app.services

import com.google.firebase.auth.FirebaseAuth
import kotlinx.coroutines.tasks.await
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

sealed class B2Error(message: String) : Exception(message) {
    object NotAuthenticated : B2Error("You must be signed in to download models.")
    class FunctionError(msg: String) : B2Error("Could not get download URL: $msg")
    object InvalidResponse : B2Error("Unexpected response from server.")
}

object B2Service {

    private const val FUNCTION_BASE =
        "https://us-central1-ecoinference-28c31.cloudfunctions.net"

    suspend fun modelDownloadUrl(modelId: String, filename: String): URL {
        val user = FirebaseAuth.getInstance().currentUser
            ?: throw B2Error.NotAuthenticated

        val idToken = user.getIdToken(false).await().token
            ?: throw B2Error.NotAuthenticated

        val body = JSONObject().apply {
            put("data", JSONObject().apply {
                put("modelId", modelId)
                put("filename", filename)
                put("platform", "mobile")
            })
        }.toString()

        val conn = URL("$FUNCTION_BASE/getModelDownloadUrl")
            .openConnection() as HttpURLConnection
        try {
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Authorization", "Bearer $idToken")
            conn.doOutput = true
            conn.connectTimeout = 15_000
            conn.readTimeout    = 15_000

            OutputStreamWriter(conn.outputStream).use { it.write(body) }

            val code = conn.responseCode
            if (code != 200) {
                val errBody = conn.errorStream?.bufferedReader()?.readText() ?: "HTTP $code"
                val msg = runCatching {
                    JSONObject(errBody).getJSONObject("error").getString("message")
                }.getOrDefault("HTTP $code")
                throw B2Error.FunctionError(msg)
            }

            val responseText = conn.inputStream.bufferedReader().readText()
            val urlStr = runCatching {
                JSONObject(responseText)
                    .getJSONObject("result")
                    .getString("url")
            }.getOrNull() ?: throw B2Error.InvalidResponse

            return URL(urlStr)
        } finally {
            conn.disconnect()
        }
    }
}
