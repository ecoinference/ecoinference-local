package ai.ecoinference.app.ui.auth

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
import ai.ecoinference.app.services.AuthService
import ai.ecoinference.app.services.UserProfileService
import ai.ecoinference.app.ui.theme.EcoColors

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen() {
    val profile        by UserProfileService.profile.collectAsState()
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
                        color = EcoColors.NearWhite.copy(alpha = 0.5f))
                },
                leadingContent = {
                    AvatarImage(urlString = profile?.avatarURL, size = 56.dp)
                },
            )

            HorizontalDivider(color = EcoColors.CardBorder)

            if (!profile?.bio.isNullOrBlank()) {
                ListItem(
                    overlineContent  = { Text("Bio", color = EcoColors.DimGreen) },
                    headlineContent  = { Text(profile!!.bio) },
                )
                HorizontalDivider(color = EcoColors.CardBorder)
            }

            ListItem(
                overlineContent  = { Text("Account", color = EcoColors.DimGreen) },
                headlineContent  = { Text("Email") },
                trailingContent  = {
                    Text(AuthService.email ?: "",
                        color = EcoColors.NearWhite.copy(alpha = 0.5f))
                },
            )

            if (!profile?.phoneNumber.isNullOrBlank()) {
                HorizontalDivider(color = EcoColors.CardBorder)
                ListItem(
                    headlineContent = { Text("Phone") },
                    trailingContent = {
                        Text(profile!!.phoneNumber!!,
                            color = EcoColors.NearWhite.copy(alpha = 0.5f))
                    },
                )
            }

            HorizontalDivider(color = EcoColors.CardBorder)

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
