package ai.ecoinference.app.router

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put

// MARK: - FactValue

/** A typed fact value. Mirrors iOS RouterModels.swift FactValue. */
@Serializable(with = FactValueSerializer::class)
sealed class FactValue {
    data class IntValue(val value: Int) : FactValue()
    data class DoubleValue(val value: Double) : FactValue()
    data class BoolValue(val value: Boolean) : FactValue()
    data class StringValue(val value: String) : FactValue()

    val asDouble: Double?
        get() = when (this) {
            is IntValue    -> value.toDouble()
            is DoubleValue -> value
            else           -> null
        }
}

object FactValueSerializer : KSerializer<FactValue> {
    override val descriptor: SerialDescriptor = JsonPrimitive.serializer().descriptor

    override fun serialize(encoder: Encoder, value: FactValue) {
        val jsonEncoder = encoder as? JsonEncoder ?: error("FactValue only supports JSON encoding")
        jsonEncoder.encodeJsonElement(toJsonElement(value))
    }

    override fun deserialize(decoder: Decoder): FactValue {
        val jsonDecoder = decoder as? JsonDecoder ?: error("FactValue only supports JSON decoding")
        return fromJsonElement(jsonDecoder.decodeJsonElement())
    }

    fun toJsonElement(value: FactValue): JsonElement = when (value) {
        is FactValue.IntValue    -> JsonPrimitive(value.value)
        is FactValue.DoubleValue -> JsonPrimitive(value.value)
        is FactValue.BoolValue   -> JsonPrimitive(value.value)
        is FactValue.StringValue -> JsonPrimitive(value.value)
    }

    fun fromJsonElement(element: JsonElement): FactValue {
        val p = element as? JsonPrimitive ?: error("FactValue must be a JSON primitive")
        return when {
            p.isString             -> FactValue.StringValue(p.content)
            p.booleanOrNull != null -> FactValue.BoolValue(p.boolean)
            p.intOrNull != null      -> FactValue.IntValue(p.int)
            p.doubleOrNull != null   -> FactValue.DoubleValue(p.double)
            else                    -> error("Unsupported FactValue: $p")
        }
    }
}

// MARK: - Conditions
//
// Shape intentionally mirrors json-rules-engine's condition format
// ({"all": [...]}, {"any": [...]}, {"fact": ..., "operator": ..., "value": ...})
// — same rationale as iOS RouterModels.swift.

@Serializable(with = RuleConditionSerializer::class)
sealed class RuleCondition {
    data class AllOf(val conditions: List<RuleCondition>) : RuleCondition()
    data class AnyOf(val conditions: List<RuleCondition>) : RuleCondition()
    data class Leaf(val fact: String, val operator: String, val value: FactValue) : RuleCondition()
}

object RuleConditionSerializer : KSerializer<RuleCondition> {
    override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor

    override fun serialize(encoder: Encoder, value: RuleCondition) {
        val jsonEncoder = encoder as? JsonEncoder ?: error("RuleCondition only supports JSON encoding")
        jsonEncoder.encodeJsonElement(toJsonElement(value))
    }

    override fun deserialize(decoder: Decoder): RuleCondition {
        val jsonDecoder = decoder as? JsonDecoder ?: error("RuleCondition only supports JSON decoding")
        return fromJsonElement(jsonDecoder.decodeJsonElement())
    }

    private fun toJsonElement(condition: RuleCondition): JsonElement = when (condition) {
        is RuleCondition.AllOf -> buildJsonObject {
            put("all", JsonArray(condition.conditions.map(::toJsonElement)))
        }
        is RuleCondition.AnyOf -> buildJsonObject {
            put("any", JsonArray(condition.conditions.map(::toJsonElement)))
        }
        is RuleCondition.Leaf -> buildJsonObject {
            put("fact", condition.fact)
            put("operator", condition.operator)
            put("value", FactValueSerializer.toJsonElement(condition.value))
        }
    }

    private fun fromJsonElement(element: JsonElement): RuleCondition {
        val obj = element as? JsonObject ?: error("RuleCondition must be a JSON object")
        (obj["all"] as? JsonArray)?.let { return RuleCondition.AllOf(it.map(::fromJsonElement)) }
        (obj["any"] as? JsonArray)?.let { return RuleCondition.AnyOf(it.map(::fromJsonElement)) }
        val fact  = (obj["fact"] as JsonPrimitive).content
        val op    = (obj["operator"] as JsonPrimitive).content
        val value = FactValueSerializer.fromJsonElement(obj["value"]!!)
        return RuleCondition.Leaf(fact, op, value)
    }
}

// MARK: - Rule / RuleSet

@Serializable
data class RouterRule(
    val id: String,
    val conditions: RuleCondition,
    /** "local" | "cloud" */
    val decision: String,
    /** Human-readable explanation, surfaced in test/debug output. */
    val reason: String,
)

@Serializable
data class RouterRuleSet(
    val version: Int,
    val rules: List<RouterRule>,
    /** "local" | "cloud" — used when no rule matches. */
    val defaultDecision: String,
)
