package com.takeed

import android.content.Context
import org.json.JSONObject

/** Small persistent store shared by the plugin, the messaging service and the open activity. */
internal object Store {
    private const val FILE = "takeed"

    private fun prefs(context: Context) = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun configure(context: Context, appId: String, apiUrl: String) {
        prefs(context).edit().putString("app_id", appId).putString("api_url", apiUrl).apply()
    }

    fun appId(context: Context): String? = prefs(context).getString("app_id", null)

    fun apiUrl(context: Context): String? = prefs(context).getString("api_url", null)

    fun saveToken(context: Context, token: String) {
        prefs(context).edit().putString("token", token).apply()
    }

    fun saveInitialClick(context: Context, payload: Map<String, Any?>) {
        prefs(context).edit().putString("initial_click", JSONObject(payload).toString()).apply()
    }

    /** Returns and clears the click that opened the app. */
    fun takeInitialClick(context: Context): Map<String, Any?>? {
        val raw = prefs(context).getString("initial_click", null) ?: return null
        prefs(context).edit().remove("initial_click").apply()
        return Json.toMap(JSONObject(raw))
    }
}
