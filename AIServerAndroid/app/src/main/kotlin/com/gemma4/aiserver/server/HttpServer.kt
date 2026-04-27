package com.gemma4.aiserver.server

import com.gemma4.aiserver.config.SettingsRepository
import com.gemma4.aiserver.download.DownloadRepository
import com.gemma4.aiserver.inference.InferenceRepository
import com.gemma4.aiserver.server.routes.catalogRoutes
import com.gemma4.aiserver.server.routes.healthRoutes
import com.gemma4.aiserver.server.routes.inferenceRoutes
import com.gemma4.aiserver.server.routes.modelRoutes
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.install
import io.ktor.server.engine.ApplicationEngine
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.server.plugins.cors.routing.CORS
import io.ktor.server.plugins.statuspages.StatusPages
import io.ktor.server.response.respond
import io.ktor.server.routing.routing
import kotlinx.coroutines.CoroutineScope
import kotlinx.serialization.json.Json

/**
 * Manages the lifecycle of the embedded Ktor/Netty HTTP server.
 *
 * Call [start] once and [stop] when the owning service is destroyed.
 * The server is not restarted automatically — create a new instance if
 * the port changes.
 */
class HttpServer(
    private val inference: InferenceRepository,
    private val download: DownloadRepository,
    private val settings: SettingsRepository,
    private val serviceScope: CoroutineScope,
) {
    private var engine: ApplicationEngine? = null

    /** Starts the HTTP server on [port]. No-op if already running. */
    fun start(port: Int) {
        if (engine != null) return

        engine = embeddedServer(
            factory = Netty,
            port = port,
            host = "0.0.0.0",
        ) {
            // ── Plugins ───────────────────────────────────────────────────────

            install(ContentNegotiation) {
                json(
                    Json {
                        ignoreUnknownKeys = true
                        encodeDefaults = true
                        explicitNulls = false
                    }
                )
            }

            install(CORS) {
                // Allow AIClient (on the same device or local network) to reach
                // this server without CORS preflight rejections.
                anyHost()
                allowHeader(HttpHeaders.ContentType)
                allowHeader(HttpHeaders.Authorization)
                allowMethod(HttpMethod.Get)
                allowMethod(HttpMethod.Post)
                allowMethod(HttpMethod.Delete)
                allowMethod(HttpMethod.Options)
            }

            install(StatusPages) {
                // Catch unhandled exceptions and return a structured JSON error
                // rather than Ktor's default HTML error page.
                exception<Throwable> { call, cause ->
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        mapOf("error" to (cause.message ?: "Internal server error")),
                    )
                }
            }

            // ── Routes ────────────────────────────────────────────────────────

            routing {
                healthRoutes(
                    inference = inference,
                    download = download,
                    settings = settings,
                )
                catalogRoutes(
                    inference = inference,
                    download = download,
                )
                modelRoutes(
                    inference = inference,
                    download = download,
                    settings = settings,
                    serviceScope = serviceScope,
                )
                inferenceRoutes(
                    inference = inference,
                )
            }
        }.start(wait = false)
    }

    /**
     * Stops the server, waiting up to [gracePeriodMillis] for in-flight
     * requests to complete before forcibly closing connections.
     */
    fun stop(gracePeriodMillis: Long = 500, timeoutMillis: Long = 2_000) {
        engine?.stop(gracePeriodMillis, timeoutMillis)
        engine = null
    }

    val isRunning: Boolean get() = engine != null
}
