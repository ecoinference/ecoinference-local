package ai.ecoinference.app.ui.models

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ai.ecoinference.app.R
import ai.ecoinference.app.AppState
import ai.ecoinference.app.ui.theme.EcoColors
import ai.ecoinference.app.ui.theme.EcoWordmark

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ModelsScreen(appState: AppState, modifier: Modifier = Modifier) {
    val models            by appState.models.collectAsStateWithLifecycle()
    val downloadActive    by appState.downloadActive.collectAsStateWithLifecycle()
    val downloadProgress  by appState.downloadProgress.collectAsStateWithLifecycle()
    val downloadingId     by appState.downloadingModelId.collectAsStateWithLifecycle()
    val downloadError     by appState.downloadError.collectAsStateWithLifecycle()
    val isLoading         by appState.isLoading.collectAsStateWithLifecycle()
    val loadError         by appState.loadError.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(downloadError) { downloadError?.let { snackbarHostState.showSnackbar(it) } }
    LaunchedEffect(loadError)     { loadError?.let     { snackbarHostState.showSnackbar(it) } }

    Scaffold(
        modifier            = modifier,
        contentWindowInsets = WindowInsets(0),
        topBar = {
            TopAppBar(
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Image(
                            painter            = painterResource(R.drawable.eco_logo),
                            contentDescription = "EcoInference logo",
                            modifier           = Modifier.size(32.dp),
                        )
                        Spacer(Modifier.width(10.dp))
                        EcoWordmark(fontSize = 20.sp)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        if (models.isEmpty()) {
            Box(
                modifier            = Modifier.fillMaxSize().padding(padding),
                contentAlignment    = Alignment.Center,
            ) {
                Text("No models available", color = EcoColors.NearWhite.copy(alpha = 0.5f))
            }
        } else {
            LazyColumn(
                modifier       = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(vertical = 8.dp),
            ) {
                items(models, key = { it.id }) { model ->
                    ModelCard(
                        model            = model,
                        isDownloading    = downloadActive && downloadingId == model.id,
                        downloadProgress = if (downloadingId == model.id) downloadProgress else 0f,
                        isLoading        = isLoading,
                        onDownload       = { appState.startDownload(model.id) },
                        onLoad           = { useGpu -> appState.loadModel(model.id, useGpu) },
                        onDelete         = { appState.deleteModel(model.id) },
                        onCancelDownload = { appState.cancelDownload() },
                    )
                }
            }
        }
    }
}
