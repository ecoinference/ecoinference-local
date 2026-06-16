import Foundation

// MARK: - FactValue

/// A typed fact value. Supports the JSON scalar types we need for router facts.
enum FactValue: Codable, Equatable {
    case int(Int)
    case double(Double)
    case bool(Bool)
    case string(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        // Bool first — JSONDecoder does not coerce between Bool and numeric types,
        // so this ordering is safe and just documents intent.
        if let b = try? c.decode(Bool.self)   { self = .bool(b);   return }
        if let i = try? c.decode(Int.self)    { self = .int(i);    return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported FactValue")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let v):    try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v):   try c.encode(v)
        case .string(let v): try c.encode(v)
        }
    }

    var asDouble: Double? {
        switch self {
        case .int(let v):    return Double(v)
        case .double(let v): return v
        default:             return nil
        }
    }
}

// MARK: - Conditions
//
// Shape intentionally mirrors json-rules-engine's condition format
// ({"all": [...]}, {"any": [...]}, {"fact": ..., "operator": ..., "value": ...})
// so the rule JSON could be swapped to run against the real JS engine later
// without reauthoring rules.

struct LeafCondition: Codable {
    let fact:     String
    let `operator`: String
    let value:    FactValue
}

indirect enum RuleCondition: Codable {
    case all([RuleCondition])
    case any([RuleCondition])
    case leaf(LeafCondition)

    private enum CodingKeys: String, CodingKey { case all, any, fact, `operator`, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let allConds = try? c.decode([RuleCondition].self, forKey: .all) {
            self = .all(allConds); return
        }
        if let anyConds = try? c.decode([RuleCondition].self, forKey: .any) {
            self = .any(anyConds); return
        }
        let fact  = try c.decode(String.self, forKey: .fact)
        let op    = try c.decode(String.self, forKey: .operator)
        let value = try c.decode(FactValue.self, forKey: .value)
        self = .leaf(LeafCondition(fact: fact, operator: op, value: value))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .all(let conds): try c.encode(conds, forKey: .all)
        case .any(let conds): try c.encode(conds, forKey: .any)
        case .leaf(let leaf):
            try c.encode(leaf.fact,     forKey: .fact)
            try c.encode(leaf.operator, forKey: .operator)
            try c.encode(leaf.value,    forKey: .value)
        }
    }
}

enum RuleOperator: String {
    case equal, notEqual
    case greaterThan, greaterThanInclusive
    case lessThan, lessThanInclusive
    case contains
}

// MARK: - Rule / RuleSet

struct RouterRule: Codable {
    let id:         String
    let conditions: RuleCondition
    /// "local" | "cloud"
    let decision:   String
    /// Human-readable explanation, surfaced in test output / future feedback UI.
    let reason:     String
}

struct RouterRuleSet: Codable {
    let version:         Int
    let rules:           [RouterRule]
    /// "local" | "cloud" — used when no rule matches.
    let defaultDecision: String
}
