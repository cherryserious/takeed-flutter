package com.takeed

import android.content.Context
import org.json.JSONObject

/** Small persistent store shared by the plugin, the messaging service and the open activity. */
internal object Store {
    private const val FILE = "takeed"

    private fun prefs(context: Context) = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /** The Takeed service. Fixed: the SDK talks to nothing else. */
    const val API_URL = "https://takeed-iq.com"

    fun configure(context: Context, appId: String) {
        prefs(context).edit().putString("app_id", appId).remove("api_url").apply()
    }

    fun appId(context: Context): String? = prefs(context).getString("app_id", null)

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
