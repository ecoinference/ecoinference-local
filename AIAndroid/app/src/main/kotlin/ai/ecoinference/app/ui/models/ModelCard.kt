package ai.ecoinference.app.ui.models

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Eject
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.ecoinference.app.models.ModelInfo
import ai.ecoinference.app.ui.theme.EcoColors

@Composable
fun ModelCard(
    model:              ModelInfo,
    isDownloading:      Boolean,
    downloadProgress:   Float,      // 0–100
    isLoading:          Boolean,
    onDownload:         () -> Unit,
    onLoad:             (useGpu: Boolean) -> Unit,
    onUnload:           () -> Unit,
    onDelete:           () -> Unit,
    onCancelDownload:   () -> Unit,
) {
    var showGpuDialog by remember { mutableStateOf(false) }
    var showHfDialog  by remember { mutableStateOf(false) }
    var hfToken       by remember { mutableStateOf("") }

    if (showGpuDialog) {
        AlertDialog(
            onDismissRequest = { showGpuDialog = false },
            title            = { Text("Load ${model.displayName}") },
            text             = { Text("Use GPU acceleration?") },
            confirmButton    = {
                TextButton(onClick = { showGpuDialog = false; onLoad(true)  }) { Text("GPU") }
            },
            dismissButton    = {
                TextButton(onClick = { showGpuDialog = false; onLoad(false) }) { Text("CPU") }
            },
        )
    }

    if (showHfDialog) {
        AlertDialog(
            onDismissRequest = { showHfDialog = false },
            title            = { Text("HuggingFace Token Required") },
            text             = {
                Column {
                    Text("This model requires accepting the licence on HuggingFace and supplying a token.")
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(
                        value         = hfToken,
                        onValueChange = { hfToken = it },
                        label         = { Text("HF Token") },
                        singleLine    = true,
                    )
                }
            },
            confirmButton    = {
                TextButton(onClick = {
                    showHfDialog = false
                    onDownload()
                    // Note: no current catalog entry sets requiresHfToken, so this
                    // dialog/path is currently unreachable. Settings no longer has
                    // an HF token field — wire [hfToken] through onDownload if this
                    // ever needs to become reachable again.
                }) { Text("Download") }
            },
            dismissButton    = {
                TextButton(onClick = { showHfDialog = false }) { Text("Cancel") }
            },
        )
    }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 6.dp),
        colors = CardDefaults.cardColors(containerColor = EcoColors.CardDark),
        border = BorderStroke(1.dp, EcoColors.CardBorder),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            // Header row
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(model.displayName, style = MaterialTheme.typography.titleMedium,
                        color = EcoColors.NearWhite)
                    if (model.description.isNotBlank()) {
                        Text(model.description, style = MaterialTheme.typography.bodySmall,
                            color = EcoColors.NearWhite.copy(alpha = 0.7f),
                            fontSize = 12.sp)
                    }
                }
                Spacer(Modifier.width(8.dp))
                // Size label
                Text(model.sizeLabel, style = MaterialTheme.typography.bodySmall,
                    color = EcoColors.DimGreen)
            }

            Spacer(Modifier.height(8.dp))

            // Badges row
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                StatusChip(when {
                    model.loaded     -> "Loaded"
                    model.downloaded -> "Downloaded"
                    else             -> "Not Downloaded"
                })
                if (model.supportsVision) StatusChip("Vision")
            }

            // Download progress
            if (isDownloading) {
                Spacer(Modifier.height(10.dp))
                LinearProgressIndicator(
                    progress     = { downloadProgress / 100f },
                    modifier     = Modifier.fillMaxWidth(),
                    color        = EcoColors.Green,
                    trackColor   = EcoColors.CardBorder,
                )
                Text("${downloadProgress.toInt()}%",
                    style = MaterialTheme.typography.bodySmall,
                    color = EcoColors.DimGreen)
            }

            Spacer(Modifier.height(12.dp))

            // Action buttons
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                when {
                    isDownloading -> {
                        OutlinedButton(
                            onClick = onCancelDownload,
                            colors  = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                            border  = BorderStroke(1.dp, MaterialTheme.colorScheme.error),
                        ) {
                            Icon(Icons.Default.Stop, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(4.dp))
                            Text("Cancel")
                        }
                    }
                    !model.downloaded -> {
                        Button(
                            onClick = {
                                if (model.requiresHfToken) showHfDialog = true else onDownload()
                            },
                            colors = ButtonDefaults.buttonColors(containerColor = EcoColors.Green,
                                contentColor = EcoColors.DarkInner),
                        ) {
                            Icon(Icons.Default.Download, contentDescription = null,
                                modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(4.dp))
                            Text("Download")
                        }
                    }
                    model.loaded -> {
                        // Unload button
                        OutlinedButton(
                            onClick = onUnload,
                            colors  = ButtonDefaults.outlinedButtonColors(
                                contentColor = EcoColors.DimGreen),
                            border  = BorderStroke(1.dp, EcoColors.Green.copy(alpha = 0.5f)),
                        ) {
                            Icon(Icons.Default.Eject, contentDescription = null,
                                modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(4.dp))
                            Text("Unload")
                        }
                        // Delete (only when loaded — unload first, then delete)
                        OutlinedButton(
                            onClick = onDelete,
                            colors  = ButtonDefaults.outlinedButtonColors(
                                contentColor = MaterialTheme.colorScheme.error),
                            border  = BorderStroke(1.dp, MaterialTheme.colorScheme.error),
                        ) {
                            Icon(Icons.Default.Delete, contentDescription = null,
                                modifier = Modifier.size(16.dp))
                        }
                    }
                    else -> {
                        // Downloaded, not loaded
                        Button(
                            onClick  = { showGpuDialog = true },
                            enabled  = !isLoading,
                            colors   = ButtonDefaults.buttonColors(containerColor = EcoColors.Green,
                                contentColor = EcoColors.DarkInner),
                        ) {
                            if (isLoading) {
                                CircularProgressIndicator(modifier = Modifier.size(16.dp),
                                    strokeWidth = 2.dp, color = EcoColors.DarkInner)
                            } else {
                                Icon(Icons.Default.PlayArrow, contentDescription = null,
                                    modifier = Modifier.size(16.dp))
                            }
                            Spacer(Modifier.width(4.dp))
                            Text(if (isLoading) "Loading…" else "Load")
                        }
                        Spacer(Modifier.width(4.dp))
                        OutlinedButton(
                            onClick = onDelete,
                            colors  = ButtonDefaults.outlinedButtonColors(
                                contentColor = MaterialTheme.colorScheme.error),
                            border  = BorderStroke(1.dp, MaterialTheme.colorScheme.error),
                        ) {
                            Icon(Icons.Default.Delete, contentDescription = null,
                                modifier = Modifier.size(16.dp))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun StatusChip(label: String) {
    Surface(
        shape  = MaterialTheme.shapes.small,
        color  = EcoColors.CardDark,
        border = BorderStroke(1.dp, EcoColors.CardBorder),
    ) {
        Text(label, modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
            style = MaterialTheme.typography.labelSmall, color = EcoColors.DimGreen)
    }
}
