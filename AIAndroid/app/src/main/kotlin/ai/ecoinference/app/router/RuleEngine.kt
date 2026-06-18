package ai.ecoinference.app.router

/** First matching rule (in declared order) wins; falls back to `defaultDecision`. */
data class RuleOutcome(
    val decision: String,   // "local" | "cloud"
    val reason: String,
    val ruleId: String?,    // null when falling back to the default decision
)

/** Evaluates a [RouterRuleSet] against a fact map. Mirrors iOS RuleEngine.swift. */
object RuleEngine {

    fun decide(facts: Map<String, FactValue>, ruleSet: RouterRuleSet): RuleOutcome {
        for (rule in ruleSet.rules) {
            if (evaluate(rule.conditions, facts)) {
                return RuleOutcome(rule.decision, rule.reason, rule.id)
            }
        }
        return RuleOutcome(ruleSet.defaultDecision, "No rule matched — default.", null)
    }

    fun evaluate(condition: RuleCondition, facts: Map<String, FactValue>): Boolean = when (condition) {
        is RuleCondition.AllOf -> condition.conditions.all { evaluate(it, facts) }
        is RuleCondition.AnyOf -> condition.conditions.any { evaluate(it, facts) }
        is RuleCondition.Leaf  -> evaluateLeaf(condition, facts)
    }

    private fun evaluateLeaf(leaf: RuleCondition.Leaf, facts: Map<String, FactValue>): Boolean {
        val factValue = facts[leaf.fact] ?: return false
        return when (leaf.operator) {
            "equal"    -> factValue == leaf.value
            "notEqual" -> factValue != leaf.value
            "greaterThan" -> compare(factValue, leaf.value) { a, b -> a > b }
            "greaterThanInclusive" -> compare(factValue, leaf.value) { a, b -> a >= b }
            "lessThan" -> compare(factValue, leaf.value) { a, b -> a < b }
            "lessThanInclusive" -> compare(factValue, leaf.value) { a, b -> a <= b }
            "contains" -> {
                val haystack = (factValue as? FactValue.StringValue)?.value
                val needle   = (leaf.value as? FactValue.StringValue)?.value
                haystack != null && needle != null && haystack.contains(needle, ignoreCase = true)
            }
            else -> false
        }
    }

    private inline fun compare(a: FactValue, b: FactValue, op: (Double, Double) -> Boolean): Boolean {
        val ad = a.asDouble ?: return false
        val bd = b.asDouble ?: return false
        return op(ad, bd)
    }
}
