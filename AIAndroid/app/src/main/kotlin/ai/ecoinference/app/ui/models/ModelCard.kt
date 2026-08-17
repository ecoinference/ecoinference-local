package ai.ecoinference.app.ui.models

import android.app.ActivityManager
import android.content.Context
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.ecoinference.app.models.ModelInfo
import ai.ecoinference.app.ui.theme.EcoColors
import ai.ecoinference.app.ui.theme.ecoBrand
import ai.ecoinference.app.ui.theme.ecoAccent

@Composable
fun ModelCard(
    model:              ModelInfo,
    isDownloading:      Boolean,
    downloadProgress:   Float,      // 0–100
    downloadSpeedText:  String = "",
    downloadEtaText:    String = "",
    isLoading:          Boolean,
    isOtherLoading:     Boolean = false,
    onDownload:         () -> Unit,
    onLoad:             (useGpu: Boolean) -> Unit,
    onUnload:           () -> Unit,
    onDelete:           () -> Unit,
    onCancelDownload:   () -> Unit,
) {
    var showGpuDialog by remember { mutableStateOf(false) }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var showRamWarning by remember { mutableStateOf(false) }

    // Total installed RAM, rounded to MB. Read once — it can't change at runtime.
    val context = LocalContext.current
    val deviceRamMb = remember {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mi = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        (mi.totalMem / (1024 * 1024)).toInt()
    }
    val ramShortfall = model.minRamMb > 0 && deviceRamMb < model.minRamMb

    // Deliberately a warning, not a hard block: E4B genuinely does load and run on
    // an 8 GB-class device — it just does so by evicting most of the OS. Someone
    // testing on purpose should be able to proceed; someone tapping Load casually
    // should be told first, because the failure mode (other apps dying, screen
    // blanking) looks like a device fault rather than a deliberate trade.
    if (showRamWarning) {
        AlertDialog(
            onDismissRequest = { showRamWarning = false },
            title            = { Text("${model.displayName} may not fit") },
            text             = {
                Text(
                    "This model wants about ${model.minRamMb / 1000} GB of RAM and this " +
                    "device has ${"%.1f".format(deviceRamMb / 1000f)} GB.\n\n" +
                    "It will probably still load, but it can push other apps out of memory — " +
                    "you may see them restart, or the screen briefly go blank. A smaller " +
                    "model will run more comfortably here."
                )
            },
            confirmButton = {
                TextButton(onClick = { showRamWarning = false; showGpuDialog = true }) {
                    Text("Load anyway")
                }
            },
            dismissButton = {
                TextButton(onClick = { showRamWarning = false }) { Text("Cancel") }
            },
        )
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title            = { Text("Delete ${model.displayName}?") },
            text             = { Text("This removes the downloaded file. You'll need to download it again to use it.") },
            confirmButton    = {
                TextButton(onClick = { showDeleteConfirm = false; onDelete() }) {
                    Text("Delete", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton    = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text("Cancel") }
            },
        )
    }

    if (showGpuDialog) {
        AlertDialog(
            onDismissRequest = { showGpuDialog = false },
            title            = { Text("Load ${model.displayName}") },
            // GPU isn't reliably the faster choice. Measured on a Mali-G57 MC2
            // tablet: the GPU path held ~2.6 GB versus ~0.75 GB on CPU for the
            // same model — the weights get copied into GPU memory instead of
            // being mapped from the file — and it produced GPU fence timeouts
            // under load. Big Adreno parts do benefit; small GPUs often don't.
            // Steer the unsure user to the safer default rather than presenting
            // two equal-looking options.
            text             = {
                Text(
                    "Use GPU acceleration?\n\n" +
                    "If you're not sure, start with CPU. It uses much less memory, " +
                    "which leaves more room for other apps. GPU may start answering " +
                    "sooner on some devices — you can reload and compare."
                )
            },
            confirmButton    = {
                TextButton(onClick = { showGpuDialog = false; onLoad(true)  }) { Text("GPU") }
            },
            dismissButton    = {
                TextButton(onClick = { showGpuDialog = false; onLoad(false) }) { Text("CPU") }
            },
        )
    }


    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 6.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            // Header row
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(model.displayName, style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurface)
                    if (model.description.isNotBlank()) {
                        Text(model.description, style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                            fontSize = 12.sp)
                    }
                }
                Spacer(Modifier.width(8.dp))
                // Size label
                Text(model.sizeLabel, style = MaterialTheme.typography.bodySmall,
                    color = ecoAccent)
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
                    color        = ecoBrand,
                    trackColor   = MaterialTheme.colorScheme.outline,
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    val leading = buildString {
                        append("${downloadProgress.toInt()}%")
                        if (downloadSpeedText.isNotEmpty()) append("  ·  $downloadSpeedText")
                    }
                    Text(leading, style = MaterialTheme.typography.bodySmall, color = ecoAccent)
                    if (downloadEtaText.isNotEmpty()) {
                        Text(downloadEtaText, style = MaterialTheme.typography.bodySmall, color = ecoAccent)
                    }
                }
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
                            onClick = { onDownload() },
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
                                contentColor = ecoAccent),
                            border  = BorderStroke(1.dp, EcoColors.Green.copy(alpha = 0.5f)),
                        ) {
                            Icon(Icons.Default.Eject, contentDescription = null,
                                modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(4.dp))
                            Text("Unload")
                        }
                        // Delete (only when loaded — unload first, then delete)
                        OutlinedButton(
                            onClick = { showDeleteConfirm = true },
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
                            onClick  = { if (ramShortfall) showRamWarning = true else showGpuDialog = true },
                            enabled  = !isLoading && !isOtherLoading,
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
                            onClick = { showDeleteConfirm = true },
                            enabled = !isLoading && !isOtherLoading,
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
        color  = MaterialTheme.colorScheme.surface,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
    ) {
        Text(label, modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
            style = MaterialTheme.typography.labelSmall, color = ecoAccent)
    }
}
