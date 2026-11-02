package com.couponproia.coupon_pro_ia

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Widget « Coupon Pro IA » de l'écran d'accueil : Coupon du jour (cote, premier match ou résultat),
 * matchs du jour et en direct, heure de mise à jour. Les textes sont préparés par l'application
 * (lib/features/widget/home_widget_sync.dart) ; un toucher ouvre l'application sur la bonne page
 * (lien couponproia://open/<page>, géré par le routeur de l'app).
 */
class CouponWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val route = widgetData.getString("route", null) ?: "/coupons"
            val views = RemoteViews(context.packageName, R.layout.coupon_widget).apply {
                setTextViewText(R.id.widget_title, widgetData.getString("title", null) ?: "Coupon du jour")
                setTextViewText(
                    R.id.widget_line1,
                    widgetData.getString("line1", null) ?: "Ouvrez l'application pour charger le coupon du jour",
                )
                setTextViewText(R.id.widget_odd, widgetData.getString("odd", null) ?: "")
                setTextViewText(R.id.widget_line2, widgetData.getString("line2", null) ?: "")
                setTextViewText(R.id.widget_updated, widgetData.getString("updated", null) ?: "")
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse("couponproia://open$route"),
                    ),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
