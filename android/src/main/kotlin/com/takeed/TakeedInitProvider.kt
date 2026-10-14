package com.takeed

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri

/**
 * Runs once when the app's process starts, before any service: starts Firebase with the
 * settings saved from Takeed, so a message can be received while Flutter isn't running.
 * Declared with a lower initOrder than Firebase's own provider, so it runs after it.
 */
class TakeedInitProvider : ContentProvider() {
    override fun onCreate(): Boolean {
        context?.let { FirebaseSetup.app(it) }
        return false
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
