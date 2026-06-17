package ai.ecoinference.app.ui.auth

import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.TextFieldColors
import androidx.compose.runtime.Composable
import ai.ecoinference.app.ui.theme.EcoColors

@Composable
fun authFieldColors(): TextFieldColors = OutlinedTextFieldDefaults.colors(
    focusedBorderColor   = EcoColors.Green,
    unfocusedBorderColor = EcoColors.CardBorder,
    focusedLabelColor    = EcoColors.Green,
    cursorColor          = EcoColors.Green,
)
