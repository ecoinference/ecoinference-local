package ai.ecoinference.app.ui.auth

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import ai.ecoinference.app.services.AuthService
import ai.ecoinference.app.services.UserProfileService
import ai.ecoinference.app.services.UsernameValidator
import ai.ecoinference.app.ui.theme.EcoColors
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private sealed class UsernameStatus {
    object Idle      : UsernameStatus()
    object Checking  : UsernameStatus()
    object Available : UsernameStatus()
    object Taken     : UsernameStatus()
    data class Invalid(val msg: String) : UsernameStatus()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateAccountSheet(onDismiss: () -> Unit) {
    var displayName      by remember { mutableStateOf("") }
    var username         by remember { mutableStateOf("") }
    var email            by remember { mutableStateOf("") }
    var password         by remember { mutableStateOf("") }
    var confirmPassword  by remember { mutableStateOf("") }
    var usernameStatus   by remember { mutableStateOf<UsernameStatus>(UsernameStatus.Idle) }
    var showPassword     by remember { mutableStateOf(false) }
    var showConfirm      by remember { mutableStateOf(false) }
    var errorMessage     by remember { mutableStateOf("") }
    var isLoading        by remember { mutableStateOf(false) }
    val scope            = rememberCoroutineScope()
    var checkJob: Job?   by remember { mutableStateOf(null) }

    val passwordMismatch = confirmPassword.isNotEmpty() && password != confirmPassword
    val canSubmit = email.isNotBlank()
        && password.length >= 8
        && !passwordMismatch
        && displayName.isNotBlank()
        && usernameStatus == UsernameStatus.Available
        && !isLoading

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
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text("Create Account", style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onSurface)

            OutlinedTextField(
                value         = displayName,
                onValueChange = { displayName = it },
                modifier      = Modifier.fillMaxWidth(),
                label         = { Text("Display Name") },
                singleLine    = true,
                colors        = authFieldColors(),
            )

            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                OutlinedTextField(
                    value         = username,
                    onValueChange = { raw ->
                        val norm = UsernameValidator.normalized(raw)
                        username = norm
                        checkJob?.cancel()
                        try {
                            UsernameValidator.validate(norm)
                            usernameStatus = UsernameStatus.Checking
                            checkJob = scope.launch {
                                delay(400)
                                usernameStatus = try {
                                    if (UserProfileService.isUsernameAvailable(norm))
                                        UsernameStatus.Available else UsernameStatus.Taken
                                } catch (_: Exception) { UsernameStatus.Idle }
                            }
                        } catch (e: UsernameValidator.ValidationError) {
                            usernameStatus = if (norm.isEmpty()) UsernameStatus.Idle
                                             else UsernameStatus.Invalid(e.message ?: "Invalid")
                        }
                    },
                    modifier  = Modifier.fillMaxWidth(),
                    label     = { Text("Username (4–16 chars, lowercase)") },
                    singleLine = true,
                    colors     = authFieldColors(),
                )
                when (val s = usernameStatus) {
                    is UsernameStatus.Available -> Text("Username is available",
                        style = MaterialTheme.typography.bodySmall, color = EcoColors.Green)
                    is UsernameStatus.Taken     -> Text("Username is already taken",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                    is UsernameStatus.Checking  -> Text("Checking…",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    is UsernameStatus.Invalid   -> Text(s.msg,
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                    else -> {}
                }
            }

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
                label                = { Text("Password (min 8 chars)") },
                singleLine           = true,
                visualTransformation = if (showPassword) VisualTransformation.None
                                       else PasswordVisualTransformation(),
                keyboardOptions      = KeyboardOptions(keyboardType = KeyboardType.Password),
                trailingIcon         = {
                    IconButton(onClick = { showPassword = !showPassword }) {
                        Icon(
                            if (showPassword) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                            contentDescription = if (showPassword) "Hide password" else "Show password",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
                colors               = authFieldColors(),
            )

            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                OutlinedTextField(
                    value                = confirmPassword,
                    onValueChange        = { confirmPassword = it },
                    modifier             = Modifier.fillMaxWidth(),
                    label                = { Text("Confirm Password") },
                    singleLine           = true,
                    visualTransformation = if (showConfirm) VisualTransformation.None
                                          else PasswordVisualTransformation(),
                    keyboardOptions      = KeyboardOptions(keyboardType = KeyboardType.Password),
                    trailingIcon         = {
                        IconButton(onClick = { showConfirm = !showConfirm }) {
                            Icon(
                                if (showConfirm) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                                contentDescription = if (showConfirm) "Hide password" else "Show password",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    },
                    colors               = authFieldColors(),
                )
                if (passwordMismatch) {
                    Text("Passwords don't match",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error)
                }
            }

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
                            val user = AuthService.createAccount(email.trim(), password)
                            UserProfileService.createProfile(
                                uid         = user.uid,
                                email       = email.trim(),
                                username    = username,
                                displayName = displayName.trim(),
                            )
                            onDismiss()
                        } catch (e: Exception) {
                            errorMessage = e.message ?: "Account creation failed."
                        } finally {
                            isLoading = false
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth(),
                enabled  = canSubmit,
                colors   = ButtonDefaults.buttonColors(
                    containerColor = EcoColors.Green,
                    contentColor   = EcoColors.DarkInner,
                ),
            ) {
                if (isLoading) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                else Text("Create Account")
            }
        }
    }
}
