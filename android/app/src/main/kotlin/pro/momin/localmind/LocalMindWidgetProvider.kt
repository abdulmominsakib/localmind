package pro.momin.localmind

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class LocalMindWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.localmind_appwidget).apply {
                val modelName = widgetData.getString("model_name", null)
                val isConfigured = widgetData.getBoolean("is_configured", false)

                if (isConfigured && !modelName.isNullOrEmpty()) {
                    setTextViewText(R.id.appwidget_model_name, modelName)
                    setTextViewText(R.id.appwidget_btn_ask_text, modelName)
                } else {
                    setTextViewText(R.id.appwidget_model_name, context.getString(R.string.widget_no_model))
                    setTextViewText(R.id.appwidget_btn_ask_text, "Ask Model")
                }

                // Search Bar -> launches chat with focus
                val searchIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("localmind://widget?action=chat")
                )
                setOnClickPendingIntent(R.id.appwidget_search_bar, searchIntent)

                // Voice Button -> launches voice assistant
                val voiceIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("localmind://widget?action=voice")
                )
                setOnClickPendingIntent(R.id.appwidget_btn_voice, voiceIntent)

                // New Chat Button -> launches new chat
                val newChatIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("localmind://widget?action=new_chat")
                )
                setOnClickPendingIntent(R.id.appwidget_btn_new_chat, newChatIntent)

                // Ask Model Button -> launches chat
                val askModelIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("localmind://widget?action=chat")
                )
                setOnClickPendingIntent(R.id.appwidget_btn_ask_model, askModelIntent)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
