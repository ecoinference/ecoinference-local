package ai.ecoinference.app.ui.auth

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.TextFieldColors
import androidx.compose.runtime.Composable
import ai.ecoinference.app.ui.theme.EcoColors
import ai.ecoinference.app.ui.theme.ecoBrand

@Composable
fun authFieldColors(): TextFieldColors = OutlinedTextFieldDefaults.colors(
    focusedBorderColor    = EcoColors.Green,
    unfocusedBorderColor  = MaterialTheme.colorScheme.outline,
    focusedLabelColor     = ecoBrand,
    unfocusedLabelColor   = MaterialTheme.colorScheme.onSurfaceVariant,
    focusedTextColor      = MaterialTheme.colorScheme.onSurface,
    unfocusedTextColor    = MaterialTheme.colorScheme.onSurface,
    focusedPlaceholderColor   = MaterialTheme.colorScheme.onSurfaceVariant,
    unfocusedPlaceholderColor = MaterialTheme.colorScheme.onSurfaceVariant,
    cursorColor           = ecoBrand,
)
