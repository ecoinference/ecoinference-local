import Foundation

/// Evaluates a `RouterRuleSet` against a fact dictionary. First matching rule
/// (in declared order) wins; falls back to `ruleSet.defaultDecision` if none match.
struct RuleEngine {

    struct Outcome {
        let decision: String   // "local" | "cloud"
        let reason:   String
        let ruleId:   String?  // nil when falling back to the default decision
    }

    func decide(facts: [String: FactValue], ruleSet: RouterRuleSet) -> Outcome {
        for rule in ruleSet.rules {
            if evaluate(rule.conditions, facts: facts) {
                return Outcome(decision: rule.decision, reason: rule.reason, ruleId: rule.id)
            }
        }
        return Outcome(decision: ruleSet.defaultDecision, reason: "No rule matched — default.", ruleId: nil)
    }

    // MARK: - Condition evaluation

    func evaluate(_ condition: RuleCondition, facts: [String: FactValue]) -> Bool {
        switch condition {
        case .all(let conds): return conds.allSatisfy { evaluate($0, facts: facts) }
        case .any(let conds): return conds.contains   { evaluate($0, facts: facts) }
        case .leaf(let leaf): return evaluate(leaf, facts: facts)
        }
    }

    private func evaluate(_ leaf: LeafCondition, facts: [String: FactValue]) -> Bool {
        guard let factValue = facts[leaf.fact] else { return false }
        guard let op = RuleOperator(rawValue: leaf.operator) else { return false }

        switch op {
        case .equal:
            return factValue == leaf.value
        case .notEqual:
            return factValue != leaf.value
        case .greaterThan:
            guard let a = factValue.asDouble, let b = leaf.value.asDouble else { return false }
            return a > b
        case .greaterThanInclusive:
            guard let a = factValue.asDouble, let b = leaf.value.asDouble else { return false }
            return a >= b
        case .lessThan:
            guard let a = factValue.asDouble, let b = leaf.value.asDouble else { return false }
            return a < b
        case .lessThanInclusive:
            guard let a = factValue.asDouble, let b = leaf.value.asDouble else { return false }
            return a <= b
        case .contains:
            guard case .string(let haystack) = factValue,
                  case .string(let needle)   = leaf.value else { return false }
            return haystack.localizedCaseInsensitiveContains(needle)
        }
    }
}
