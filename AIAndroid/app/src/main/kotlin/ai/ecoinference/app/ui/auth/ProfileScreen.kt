package ai.ecoinference.app.ui.auth

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import android.content.Intent
import androidx.compose.material.icons.filled.Share
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ai.ecoinference.app.services.AuthService
import ai.ecoinference.app.services.SettingsService
import ai.ecoinference.app.services.UserProfileService
import ai.ecoinference.app.ui.theme.EcoColors
import ai.ecoinference.app.ui.theme.ecoAccent
import androidx.compose.ui.platform.LocalContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen() {
    val context        = LocalContext.current
    val settings       = remember { SettingsService.getInstance(context) }
    val profile        by UserProfileService.profile.collectAsState()
    val localCount     by settings.lifetimeLocalCountFlow.collectAsStateWithLifecycle(0)
    val cloudCount     by settings.lifetimeCloudCountFlow.collectAsStateWithLifecycle(0)
    var showEdit       by remember { mutableStateOf(false) }
    var showSignOut    by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title  = { Text("Profile") },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background),
                actions = {
                    TextButton(onClick = { showEdit = true }) {
                        Text("Edit", color = EcoColors.Green)
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // ── Avatar + name row ─────────────────────────────────────────────
            ListItem(
                headlineContent = {
                    Text(profile?.displayName ?: "—",
                        style = MaterialTheme.typography.titleMedium)
                },
                supportingContent = {
                    Text("@${profile?.username ?: ""}",
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                },
                leadingContent = {
                    AvatarImage(urlString = profile?.avatarURL, size = 56.dp)
                },
            )

            HorizontalDivider(color = MaterialTheme.colorScheme.outline)

            if (!profile?.bio.isNullOrBlank()) {
                ListItem(
                    overlineContent  = { Text("Bio", color = ecoAccent) },
                    headlineContent  = { Text(profile!!.bio) },
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outline)
            }

            ListItem(
                overlineContent  = { Text("Account", color = ecoAccent) },
                headlineContent  = { Text("Email") },
                trailingContent  = {
                    Text(AuthService.email ?: "",
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                },
            )

            if (!profile?.phoneNumber.isNullOrBlank()) {
                HorizontalDivider(color = MaterialTheme.colorScheme.outline)
                ListItem(
                    headlineContent = { Text("Phone") },
                    trailingContent = {
                        Text(profile!!.phoneNumber!!,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    },
                )
            }

            HorizontalDivider(color = MaterialTheme.colorScheme.outline)

            // ── Impact section ────────────────────────────────────────────────
            val total = localCount + cloudCount
            val pct   = if (total > 0) (localCount * 100 / total) else 0
            ListItem(
                overlineContent = { Text("Impact", color = ecoAccent) },
                headlineContent = { Text("On-device responses") },
                trailingContent = {
                    Text("$localCount", color = EcoColors.Green,
                        style = MaterialTheme.typography.titleMedium)
                },
            )
            ListItem(
                headlineContent = { Text("Cloud responses") },
                trailingContent = {
                    Text("$cloudCount",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.titleMedium)
                },
            )
            if (total > 0) {
                ListItem(
                    headlineContent = { Text("On-device rate") },
                    trailingContent = {
                        Text("$pct%",
                            color = if (pct >= 80) EcoColors.Green else MaterialTheme.colorScheme.onSurface,
                            style = MaterialTheme.typography.titleMedium)
                    },
                )
                val shareText = "🌿 $localCount of $total questions answered on-device ($pct%)\nvia EcoInference — local-first AI"
                ListItem(
                    headlineContent = { Text("Share my stats") },
                    leadingContent  = {
                        Icon(Icons.Default.Share, contentDescription = null,
                            tint = EcoColors.Green)
                    },
                    modifier = Modifier.clickable {
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, shareText)
                        }
                        context.startActivity(Intent.createChooser(intent, "Share stats"))
                    }
                )
            }

            HorizontalDivider(color = MaterialTheme.colorScheme.outline)

            ListItem(
                headlineContent = {
                    Text("Sign Out", color = MaterialTheme.colorScheme.error)
                },
                modifier = Modifier.padding(top = 8.dp),
                leadingContent = null,
                trailingContent = null,
                supportingContent = null,
            )
            // Sign out tappable row
            TextButton(
                onClick  = { showSignOut = true },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                colors   = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
            ) { Text("Sign Out") }
        }
    }

    if (showEdit) {
        EditProfileSheet(onDismiss = { showEdit = false })
    }

    if (showSignOut) {
        AlertDialog(
            onDismissRequest = { showSignOut = false },
            title   = { Text("Sign Out") },
            text    = { Text("Are you sure you want to sign out?") },
            confirmButton = {
                TextButton(onClick = {
                    showSignOut = false
                    AuthService.signOut()
                }) { Text("Sign Out", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { showSignOut = false }) { Text("Cancel") }
            },
        )
    }
}

@Composable
fun AvatarImage(urlString: String?, size: Dp) {
    if (!urlString.isNullOrBlank()) {
        AsyncImage(
            model               = urlString,
            contentDescription  = "Avatar",
            contentScale        = ContentScale.Crop,
            modifier            = Modifier.size(size).clip(CircleShape),
        )
    } else {
        Icon(
            Icons.Default.Person,
            contentDescription = "Avatar",
            tint     = EcoColors.Green,
            modifier = Modifier.size(size),
        )
    }
}
