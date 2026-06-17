package ai.ecoinference.app.ui.auth

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MarkEmailRead
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import ai.ecoinference.app.services.AuthService
import ai.ecoinference.app.ui.theme.EcoColors
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ForgotPasswordSheet(onDismiss: () -> Unit) {
    var email        by remember { mutableStateOf("") }
    var sent         by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf("") }
    var isLoading    by remember { mutableStateOf(false) }
    val scope        = rememberCoroutineScope()

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor   = MaterialTheme.colorScheme.surface,
    ) {
        Column(
            modifier            = Modifier
                .fillMaxWidth()
                .padding(horizontal = 28.dp)
                .padding(bottom = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Reset Password", style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onSurface)

            if (sent) {
                Icon(Icons.Default.MarkEmailRead, contentDescription = null,
                    tint = EcoColors.Green, modifier = Modifier.size(56.dp))
                Text("Check your email", style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface)
                Text("A reset link was sent to $email.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center)
                Button(
                    onClick = onDismiss,
                    modifier = Modifier.fillMaxWidth(),
                    colors   = ButtonDefaults.buttonColors(
                        containerColor = EcoColors.Green,
                        contentColor   = EcoColors.DarkInner,
                    ),
                ) { Text("Done") }
            } else {
                Text(
                    "Enter your email address and we'll send a password reset link.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
                OutlinedTextField(
                    value           = email,
                    onValueChange   = { email = it },
                    modifier        = Modifier.fillMaxWidth(),
                    label           = { Text("Email") },
                    singleLine      = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    colors          = authFieldColors(),
                )
                if (errorMessage.isNotEmpty()) {
                    Text(errorMessage, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error)
                }
                Button(
                    onClick  = {
                        scope.launch {
                            isLoading    = true
                            errorMessage = ""
                            try {
                                AuthService.sendPasswordReset(email.trim())
                                sent = true
                            } catch (e: Exception) {
                                errorMessage = e.message ?: "Failed to send reset email."
                            } finally {
                                isLoading = false
                            }
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                    enabled  = email.isNotBlank() && !isLoading,
                    colors   = ButtonDefaults.buttonColors(
                        containerColor = EcoColors.Green,
                        contentColor   = EcoColors.DarkInner,
                    ),
                ) {
                    if (isLoading) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    else Text("Send Reset Email")
                }
            }
        }
    }
}
