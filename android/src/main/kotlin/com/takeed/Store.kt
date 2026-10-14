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

    /** Firebase settings from Takeed; saved so a cold start can start Firebase before Flutter runs. */
    fun saveFirebase(context: Context, settings: FirebaseSetup.Settings) {
        prefs(context).edit()
            .putString("fb_project_id", settings.projectId)
            .putString("fb_app_id", settings.appId)
            .putString("fb_api_key", settings.apiKey)
            .putString("fb_sender_id", settings.senderId)
            .putString("fb_storage_bucket", settings.storageBucket)
            .apply()
    }

    fun firebase(context: Context): FirebaseSetup.Settings? {
        val p = prefs(context)
        return FirebaseSetup.Settings(
            projectId = p.getString("fb_project_id", null) ?: return null,
            appId = p.getString("fb_app_id", null) ?: return null,
            apiKey = p.getString("fb_api_key", null) ?: return null,
            senderId = p.getString("fb_sender_id", null) ?: return null,
            storageBucket = p.getString("fb_storage_bucket", null),
        )
    }

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
