package ai.ecoinference.app.services

object UsernameValidator {
    private val regex = Regex("^[a-z0-9_]{4,16}$")

    sealed class ValidationError(msg: String) : Exception(msg) {
        object TooShort     : ValidationError("Username must be at least 4 characters.")
        object TooLong      : ValidationError("Username must be 16 characters or fewer.")
        object InvalidChars : ValidationError("Only lowercase letters, numbers, and underscores.")
    }

    fun validate(username: String) {
        if (username.length < 4)  throw ValidationError.TooShort
        if (username.length > 16) throw ValidationError.TooLong
        if (!regex.matches(username)) throw ValidationError.InvalidChars
    }

    fun normalized(raw: String): String = raw.lowercase().trim()
}
