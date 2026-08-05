package ai.ecoinference.app.ui.auth

import android.graphics.Bitmap
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import ai.ecoinference.app.services.AuthService
import ai.ecoinference.app.services.StorageService
import ai.ecoinference.app.services.UserProfileService
import ai.ecoinference.app.ui.theme.EcoColors
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditProfileSheet(onDismiss: () -> Unit) {
    val profile     by UserProfileService.profile.collectAsState()
    val context     = LocalContext.current
    val scope       = rememberCoroutineScope()

    var displayName  by remember(profile) { mutableStateOf(profile?.displayName ?: "") }
    var bio          by remember(profile) { mutableStateOf(profile?.bio ?: "") }
    var phoneNumber  by remember(profile) { mutableStateOf(profile?.phoneNumber ?: "") }
    var pendingUri   by remember { mutableStateOf<Uri?>(null) }
    var isLoading    by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf("") }

    val imagePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.GetContent()
    ) { uri -> pendingUri = uri }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor   = MaterialTheme.colorScheme.surface,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp)
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment     = Alignment.CenterVertically,
            ) {
                TextButton(onClick = onDismiss) {
                    Text("Cancel",
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f))
                }
                Text("Edit Profile", style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface)
                TextButton(
                    onClick  = {
                        scope.launch {
                            val uid = AuthService.uid ?: return@launch
                            isLoading    = true
                            errorMessage = ""
                            try {
                                val fields = mutableMapOf<String, Any?>(
                                    "displayName" to displayName.trim(),
                                    "bio"         to bio.trim(),
                                    "phoneNumber" to phoneNumber.trim(),
                                )
                                if (pendingUri != null) {
                                    val bitmap = loadBitmap(context, pendingUri!!)
                                    if (bitmap != null) {
                                        fields["avatarURL"] = StorageService.uploadAvatar(uid, bitmap)
                                    }
                                }
                                UserProfileService.updateProfile(uid, fields)
                                onDismiss()
                            } catch (e: Exception) {
                                errorMessage = e.message ?: "Save failed."
                            } finally {
                                isLoading = false
                            }
                        }
                    },
                    enabled = !isLoading && displayName.isNotBlank(),
                ) { Text("Save", color = EcoColors.Green) }
            }

            // ── Avatar picker ─────────────────────────────────────────────────
            Box(contentAlignment = Alignment.BottomEnd) {
                if (pendingUri != null) {
                    AsyncImage(
                        model               = ImageRequest.Builder(context).data(pendingUri).build(),
                        contentDescription  = "Avatar",
                        contentScale        = ContentScale.Crop,
                        modifier            = Modifier.size(80.dp).clip(CircleShape)
                            .clickable { imagePicker.launch("image/*") },
                    )
                } else {
                    AvatarImage(urlString = profile?.avatarURL, size = 80.dp)
                    Box(Modifier.clickable { imagePicker.launch("image/*") })
                }
                Icon(Icons.Default.Edit, contentDescription = "Pick avatar",
                    tint = EcoColors.Green,
                    modifier = Modifier.size(24.dp)
                        .clickable { imagePicker.launch("image/*") })
            }

            OutlinedTextField(
                value         = displayName,
                onValueChange = { displayName = it },
                modifier      = Modifier.fillMaxWidth(),
                label         = { Text("Display Name") },
                singleLine    = true,
                colors        = authFieldColors(),
            )
            OutlinedTextField(
                value         = bio,
                onValueChange = { bio = it },
                modifier      = Modifier.fillMaxWidth().heightIn(min = 80.dp),
                label         = { Text("Bio") },
                maxLines      = 5,
                colors        = authFieldColors(),
            )
            OutlinedTextField(
                value         = phoneNumber,
                onValueChange = { phoneNumber = it },
                modifier      = Modifier.fillMaxWidth(),
                label         = { Text("Phone (optional)") },
                singleLine    = true,
                colors        = authFieldColors(),
            )

            if (errorMessage.isNotEmpty()) {
                Text(errorMessage, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error)
            }
            if (isLoading) {
                CircularProgressIndicator(color = EcoColors.Green)
            }
        }
    }
}

private fun loadBitmap(context: android.content.Context, uri: Uri): Bitmap? {
    return try {
        val source = android.graphics.ImageDecoder.createSource(context.contentResolver, uri)
        android.graphics.ImageDecoder.decodeBitmap(source) { decoder, _, _ ->
            decoder.allocator = android.graphics.ImageDecoder.ALLOCATOR_SOFTWARE
        }
    } catch (_: Exception) { null }
}
