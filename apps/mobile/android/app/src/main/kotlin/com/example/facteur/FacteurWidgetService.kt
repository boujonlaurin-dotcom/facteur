package com.example.facteur

import android.content.Intent
import android.widget.RemoteViewsService

/**
 * Bridges the home-screen widget ListView to a RemoteViewsFactory that
 * reads SharedPreferences (populated by Flutter via `home_widget`) and
 * inflates one row per digest article.
 */
class FacteurWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return FacteurWidgetRemoteViewsFactory(applicationContext)
    }
}
