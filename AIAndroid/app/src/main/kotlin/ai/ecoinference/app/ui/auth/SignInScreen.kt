package ai.ecoinference.app.ui.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.ecoinference.app.services.AuthService
import ai.ecoinference.app.ui.theme.EcoColors
import ai.ecoinference.app.ui.theme.EcoWordmark
import kotlinx.coroutines.launch

@Composable
fun SignInScreen() {
    var email          by remember { mutableStateOf("") }
    var password       by remember { mutableStateOf("") }
    var errorMessage   by remember { mutableStateOf("") }
    var isLoading      by remember { mutableStateOf(false) }
    var showPassword   by remember { mutableStateOf(false) }
    var showCreate     by remember { mutableStateOf(false) }
    var showForgot     by remember { mutableStateOf(false) }
    val scope          = rememberCoroutineScope()

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(horizontal = 28.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(0.dp),
        ) {
            Spacer(Modifier.weight(1f))

            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                EcoWordmark(fontSize = 32.sp)
                Text(
                    "On-device AI",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f),
                )
            }

            Spacer(Modifier.weight(1f))

            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                OutlinedTextField(
                    value         = email,
                    onValueChange = { email = it },
                    modifier      = Modifier.fillMaxWidth(),
                    label         = { Text("Email") },
                    singleLine    = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    colors        = authFieldColors(),
                )
                OutlinedTextField(
                    value                = password,
                    onValueChange        = { password = it },
                    modifier             = Modifier.fillMaxWidth(),
                    label                = { Text("Password") },
                    singleLine           = true,
                    visualTransformation = if (showPassword) VisualTransformation.None
                                          else PasswordVisualTransformation(),
                    keyboardOptions      = KeyboardOptions(keyboardType = KeyboardType.Password),
                    trailingIcon         = {
                        IconButton(onClick = { showPassword = !showPassword }) {
                            Icon(
                                if (showPassword) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                                contentDescription = if (showPassword) "Hide password" else "Show password",
                                tint = EcoColors.NearWhite.copy(alpha = 0.6f),
                            )
                        }
                    },
                    colors               = authFieldColors(),
                )
                if (errorMessage.isNotEmpty()) {
                    Text(
                        errorMessage,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
                Button(
                    onClick  = {
                        scope.launch {
                            isLoading    = true
                            errorMessage = ""
                            try {
                                AuthService.signIn(email.trim(), password)
                            } catch (e: Exception) {
                                errorMessage = e.message ?: "Sign-in failed."
                            } finally {
                                isLoading = false
                            }
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                    enabled  = !isLoading && email.isNotBlank() && password.isNotBlank(),
                    colors   = ButtonDefaults.buttonColors(
                        containerColor = EcoColors.Green,
                        contentColor   = EcoColors.DarkInner,
                    ),
                ) {
                    if (isLoading) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    else Text("Sign In")
                }
            }

            Spacer(Modifier.height(12.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                TextButton(onClick = { showForgot = true }) {
                    Text("Forgot Password?", color = EcoColors.Green,
                        style = MaterialTheme.typography.bodySmall)
                }
                TextButton(onClick = { showCreate = true }) {
                    Text("Create Account", color = EcoColors.Green,
                        style = MaterialTheme.typography.bodySmall)
                }
            }

            Spacer(Modifier.weight(1f))
        }
    }

    if (showCreate) {
        CreateAccountSheet(onDismiss = { showCreate = false })
    }
    if (showForgot) {
        ForgotPasswordSheet(onDismiss = { showForgot = false })
    }
}
