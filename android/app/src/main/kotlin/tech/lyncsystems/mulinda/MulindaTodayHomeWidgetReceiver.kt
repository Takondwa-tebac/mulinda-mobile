// GENERATED CODE - DO NOT MODIFY BY HAND
package tech.lyncsystems.mulinda

import android.content.Context
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver

class MulindaTodayHomeWidgetReceiver : HomeWidgetGlanceWidgetReceiver<MulindaTodayHomeWidget>() {
  override val glanceAppWidget = MulindaTodayHomeWidget()

  override fun previewFingerprint(context: Context): String =
      glanceAppWidget.previewFingerprint(context)
}
