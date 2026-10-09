package com.takeed

import org.json.JSONArray
import org.json.JSONObject

internal object Json {
    fun toMap(obj: JSONObject): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        val keys = obj.keys()
        while (keys.hasNext()) {
            val k = keys.next()
            out[k] = convert(obj.opt(k))
        }
        return out
    }

    fun toList(arr: JSONArray): List<Any?> = (0 until arr.length()).map { convert(arr.opt(it)) }

    private fun convert(v: Any?): Any? = when (v) {
        is JSONObject -> toMap(v)
        is JSONArray -> toList(v)
        JSONObject.NULL -> null
        else -> v
    }

    fun parseObject(raw: String?): Map<String, Any?>? = try {
        if (raw.isNullOrEmpty()) null else toMap(JSONObject(raw))
    } catch (e: Exception) {
        null
    }

    fun parseArray(raw: String?): List<Map<String, Any?>> = try {
        if (raw.isNullOrEmpty()) emptyList() else toList(JSONArray(raw)).filterIsInstance<Map<String, Any?>>()
    } catch (e: Exception) {
        emptyList()
    }
}
