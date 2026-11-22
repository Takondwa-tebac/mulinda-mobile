// GENERATED CODE - DO NOT MODIFY BY HAND
//
// This is a placeholder Glance (Jetpack Compose) widget.
package tech.lyncsystems.mulinda

import androidx.compose.runtime.Composable
import android.content.Context
import androidx.compose.ui.graphics.Color
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Box
import androidx.glance.layout.fillMaxSize
import androidx.glance.text.Text
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetPlugin
import androidx.glance.LocalSize
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.layout.Column
import androidx.glance.layout.Alignment
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.text.TextStyle
import androidx.glance.color.ColorProvider
import androidx.compose.ui.unit.sp
import androidx.glance.text.FontWeight
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.layout.height
import androidx.glance.appwidget.cornerRadius
import androidx.glance.layout.fillMaxHeight
import androidx.core.os.ConfigurationCompat
import java.util.Locale
import androidx.glance.GlanceTheme
import androidx.glance.appwidget.SizeMode
import androidx.glance.action.clickable
import androidx.glance.action.actionStartActivity

class MulindaTodayHomeWidget : GlanceAppWidget() {
  override val stateDefinition = HomeWidgetGlanceStateDefinition()

  override val sizeMode = SizeMode.Responsive(
      setOf(
          DpSize(110.dp, 110.dp),
          DpSize(250.dp, 110.dp),
          DpSize(250.dp, 250.dp),
          DpSize(530.dp, 250.dp),
          DpSize(250.dp, 530.dp),
      )
  )
  override val previewSizeMode = sizeMode

  override suspend fun provideGlance(context: Context, id: GlanceId) {
    provideContent { WidgetContent(context, currentState()) }
  }

  override suspend fun providePreview(context: Context, widgetCategory: Int) {
    provideContent { WidgetContent(context, HomeWidgetGlanceState(HomeWidgetPlugin.getData(context))) }
  }

  fun previewFingerprint(context: Context): String {
    val hwLocales = hwCurrentLocales(context)
    val hwPreviewData =
        MulindaTodayData.fromPreferences(HomeWidgetPlugin.getData(context))
    return listOf(
      "52e7b178",
      hwLocales.joinToString(","),
      hwPreviewData.toString(),
    ).joinToString("|")
  }

  @Composable
  private fun WidgetContent(context: Context, currentState: HomeWidgetGlanceState) {
    val prefs = currentState.preferences
    val widgetData = MulindaTodayData.fromPreferences(prefs)
    GlanceTheme {
            Box(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFFFFFFF), night = Color(0xFF121413))).padding(16.dp).fillMaxSize().clickable(onClick = actionStartActivity<MainActivity>()), contentAlignment = Alignment.Center) {
                if (widgetData.hasData == true) {
                    when (LocalSize.current) {
                        DpSize(250.dp, 110.dp), DpSize(250.dp, 250.dp), DpSize(530.dp, 250.dp), DpSize(250.dp, 530.dp) -> {
                            Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                                Column(modifier = GlanceModifier.defaultWeight(), horizontalAlignment = Alignment.Start) {
                                    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                        Text(text = widgetData.title ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF1C1B1B), night = Color(0xFFE5E2E1)), fontSize = 15.sp, fontWeight = FontWeight.Bold))
                                        Spacer(modifier = GlanceModifier.defaultWeight())
                                        Text(text = widgetData.streak ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF1C1B1B), night = Color(0xFFE5E2E1)), fontSize = 15.sp, fontWeight = FontWeight.Bold))
                                    }
                                    Text(modifier = GlanceModifier.padding(top = 5.0.dp), text = widgetData.spent ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF1C1B1B), night = Color(0xFFE5E2E1)), fontSize = 24.sp, fontWeight = FontWeight.Bold))
                                    Row(modifier = GlanceModifier.padding(top = 5.0.dp), verticalAlignment = Alignment.CenterVertically) {
                                        if (widgetData.bar1 == true) {
                                            if (widgetData.over == true) {
                                                Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFFF9F1C), night = Color(0xFFFF9F1C))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                            } else {
                                                Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFF2EC4B6), night = Color(0xFF2EC4B6))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                            }
                                        } else {
                                            Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFE5E2E1), night = Color(0xFF2A2E2C))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                        }
                                        if (widgetData.bar2 == true) {
                                            if (widgetData.over == true) {
                                                Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                                    Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFFF9F1C), night = Color(0xFFFF9F1C))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                                }
                                            } else {
                                                Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                                    Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFF2EC4B6), night = Color(0xFF2EC4B6))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                                }
                                            }
                                        } else {
                                            Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                                Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFE5E2E1), night = Color(0xFF2A2E2C))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                            }
                                        }
                                        if (widgetData.bar3 == true) {
                                            if (widgetData.over == true) {
                                                Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                                    Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFFF9F1C), night = Color(0xFFFF9F1C))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                                }
                                            } else {
                                                Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                                    Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFF2EC4B6), night = Color(0xFF2EC4B6))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                                }
                                            }
                                        } else {
                                            Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                                Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFE5E2E1), night = Color(0xFF2A2E2C))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                            }
                                        }
                                        if (widgetData.bar4 == true) {
                                            if (widgetData.over == true) {
                                                Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                                    Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFFF9F1C), night = Color(0xFFFF9F1C))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                                }
                                            } else {
                                                Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                                    Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFF2EC4B6), night = Color(0xFF2EC4B6))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                                }
                                            }
                                        } else {
                                            Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                                Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFE5E2E1), night = Color(0xFF2A2E2C))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                            }
                                        }
                                        if (widgetData.bar5 == true) {
                                            if (widgetData.over == true) {
                                                Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                                    Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFFF9F1C), night = Color(0xFFFF9F1C))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                                }
                                            } else {
                                                Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                                    Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFF2EC4B6), night = Color(0xFF2EC4B6))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                                }
                                            }
                                        } else {
                                            Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                                Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFE5E2E1), night = Color(0xFF2A2E2C))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                            }
                                        }
                                    }
                                    Text(modifier = GlanceModifier.padding(top = 5.0.dp), text = widgetData.left ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF3C4947), night = Color(0xFFBBCAC6)), fontSize = 12.sp))
                                    Box(modifier = GlanceModifier.fillMaxWidth().padding(top = 5.0.dp)) {
                                        Row(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFF0EDED), night = Color(0xFF1E211F))).cornerRadius(10.0.dp).padding(start = 8.0.dp, top = 6.0.dp, end = 8.0.dp, bottom = 6.0.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                            Text(text = widgetData.lastTxn ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF1C1B1B), night = Color(0xFFE5E2E1)), fontSize = 12.sp, fontWeight = FontWeight.Medium))
                                            Spacer(modifier = GlanceModifier.defaultWeight())
                                            Text(text = widgetData.lastAmount ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF1C1B1B), night = Color(0xFFE5E2E1)), fontSize = 12.sp, fontWeight = FontWeight.Medium))
                                        }
                                    }
                                }
                                Box(modifier = GlanceModifier.padding(start = 10.0.dp)) {
                                    Column(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFF0EDED), night = Color(0xFF1E211F))).cornerRadius(14.0.dp).padding(start = 10.0.dp, top = 10.0.dp, end = 10.0.dp, bottom = 10.0.dp).width(112.0.dp), horizontalAlignment = Alignment.Start) {
                                        Text(text = widgetData.challengeLabel ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFFA35F00), night = Color(0xFFFFBF69)), fontSize = 10.sp, fontWeight = FontWeight.Bold))
                                        Text(modifier = GlanceModifier.padding(top = 4.0.dp), text = widgetData.challengeText ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF1C1B1B), night = Color(0xFFE5E2E1)), fontSize = 12.sp, fontWeight = FontWeight.Medium))
                                        if (widgetData.over == true) {
                                            Text(modifier = GlanceModifier.padding(top = 4.0.dp), text = widgetData.challengeStatus ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFFFF9F1C), night = Color(0xFFFF9F1C)), fontSize = 11.sp, fontWeight = FontWeight.Bold))
                                        } else {
                                            Text(modifier = GlanceModifier.padding(top = 4.0.dp), text = widgetData.challengeStatus ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF2EC4B6), night = Color(0xFF2EC4B6)), fontSize = 11.sp, fontWeight = FontWeight.Bold))
                                        }
                                    }
                                }
                            }
                        }
                        else -> {
                            Column(horizontalAlignment = Alignment.Start) {
                                Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                    Text(text = widgetData.title ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF1C1B1B), night = Color(0xFFE5E2E1)), fontSize = 15.sp, fontWeight = FontWeight.Bold))
                                    Spacer(modifier = GlanceModifier.defaultWeight())
                                    Text(text = widgetData.streak ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF1C1B1B), night = Color(0xFFE5E2E1)), fontSize = 15.sp, fontWeight = FontWeight.Bold))
                                }
                                Text(modifier = GlanceModifier.padding(top = 6.0.dp), text = widgetData.spent ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF1C1B1B), night = Color(0xFFE5E2E1)), fontSize = 24.sp, fontWeight = FontWeight.Bold))
                                Row(modifier = GlanceModifier.padding(top = 6.0.dp), verticalAlignment = Alignment.CenterVertically) {
                                    if (widgetData.bar1 == true) {
                                        if (widgetData.over == true) {
                                            Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFFF9F1C), night = Color(0xFFFF9F1C))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                        } else {
                                            Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFF2EC4B6), night = Color(0xFF2EC4B6))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                        }
                                    } else {
                                        Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFE5E2E1), night = Color(0xFF2A2E2C))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                    }
                                    if (widgetData.bar2 == true) {
                                        if (widgetData.over == true) {
                                            Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                                Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFFF9F1C), night = Color(0xFFFF9F1C))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                            }
                                        } else {
                                            Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                                Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFF2EC4B6), night = Color(0xFF2EC4B6))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                            }
                                        }
                                    } else {
                                        Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                            Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFE5E2E1), night = Color(0xFF2A2E2C))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                        }
                                    }
                                    if (widgetData.bar3 == true) {
                                        if (widgetData.over == true) {
                                            Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                                Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFFF9F1C), night = Color(0xFFFF9F1C))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                            }
                                        } else {
                                            Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                                Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFF2EC4B6), night = Color(0xFF2EC4B6))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                            }
                                        }
                                    } else {
                                        Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                            Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFE5E2E1), night = Color(0xFF2A2E2C))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                        }
                                    }
                                    if (widgetData.bar4 == true) {
                                        if (widgetData.over == true) {
                                            Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                                Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFFF9F1C), night = Color(0xFFFF9F1C))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                            }
                                        } else {
                                            Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                                Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFF2EC4B6), night = Color(0xFF2EC4B6))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                            }
                                        }
                                    } else {
                                        Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                            Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFE5E2E1), night = Color(0xFF2A2E2C))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                        }
                                    }
                                    if (widgetData.bar5 == true) {
                                        if (widgetData.over == true) {
                                            Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                                Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFFF9F1C), night = Color(0xFFFF9F1C))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                            }
                                        } else {
                                            Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                                Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFF2EC4B6), night = Color(0xFF2EC4B6))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                            }
                                        }
                                    } else {
                                        Box(modifier = GlanceModifier.padding(start = 4.0.dp)) {
                                            Spacer(modifier = GlanceModifier.background(ColorProvider(day = Color(0xFFE5E2E1), night = Color(0xFF2A2E2C))).cornerRadius(3.0.dp).width(20.0.dp).height(6.0.dp))
                                        }
                                    }
                                }
                                Text(modifier = GlanceModifier.padding(top = 6.0.dp), text = widgetData.left ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF3C4947), night = Color(0xFFBBCAC6)), fontSize = 12.sp))
                            }
                        }
                    }
                } else {
                    Column(modifier = GlanceModifier.fillMaxHeight(), horizontalAlignment = Alignment.Start) {
                        Spacer(modifier = GlanceModifier.defaultWeight())
                        Text(text = widgetData.title ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF1C1B1B), night = Color(0xFFE5E2E1)), fontSize = 15.sp, fontWeight = FontWeight.Bold))
                        Text(modifier = GlanceModifier.padding(top = 4.0.dp), text = widgetData.emptyText ?: "", style = TextStyle(color = ColorProvider(day = Color(0xFF3C4947), night = Color(0xFFBBCAC6)), fontSize = 12.sp))
                        Spacer(modifier = GlanceModifier.defaultWeight())
                    }
                }
            }
    }

  }
}

data class MulindaTodayData(
    val hasData: Boolean? = null,
    val title: String? = null,
    val streak: String? = null,
    val spent: String? = null,
    val bar1: Boolean? = null,
    val over: Boolean? = null,
    val bar2: Boolean? = null,
    val bar3: Boolean? = null,
    val bar4: Boolean? = null,
    val bar5: Boolean? = null,
    val left: String? = null,
    val lastTxn: String? = null,
    val lastAmount: String? = null,
    val challengeLabel: String? = null,
    val challengeText: String? = null,
    val challengeStatus: String? = null,
    val emptyText: String? = null,
) {
    companion object {
        private const val PREFERENCES_PREFIX = "home_widget.MulindaToday"

        fun fromPreferences(prefs: android.content.SharedPreferences): MulindaTodayData {
            return MulindaTodayData(
                hasData = if (prefs.contains("${PREFERENCES_PREFIX}.hasData")) prefs.getBoolean("${PREFERENCES_PREFIX}.hasData", false) else false,
                title = prefs.getString("${PREFERENCES_PREFIX}.title", "Today"),
                streak = prefs.getString("${PREFERENCES_PREFIX}.streak", ""),
                spent = prefs.getString("${PREFERENCES_PREFIX}.spent", "MK 0"),
                bar1 = if (prefs.contains("${PREFERENCES_PREFIX}.bar1")) prefs.getBoolean("${PREFERENCES_PREFIX}.bar1", false) else false,
                over = if (prefs.contains("${PREFERENCES_PREFIX}.over")) prefs.getBoolean("${PREFERENCES_PREFIX}.over", false) else false,
                bar2 = if (prefs.contains("${PREFERENCES_PREFIX}.bar2")) prefs.getBoolean("${PREFERENCES_PREFIX}.bar2", false) else false,
                bar3 = if (prefs.contains("${PREFERENCES_PREFIX}.bar3")) prefs.getBoolean("${PREFERENCES_PREFIX}.bar3", false) else false,
                bar4 = if (prefs.contains("${PREFERENCES_PREFIX}.bar4")) prefs.getBoolean("${PREFERENCES_PREFIX}.bar4", false) else false,
                bar5 = if (prefs.contains("${PREFERENCES_PREFIX}.bar5")) prefs.getBoolean("${PREFERENCES_PREFIX}.bar5", false) else false,
                left = prefs.getString("${PREFERENCES_PREFIX}.left", ""),
                lastTxn = prefs.getString("${PREFERENCES_PREFIX}.lastTxn", ""),
                lastAmount = prefs.getString("${PREFERENCES_PREFIX}.lastAmount", ""),
                challengeLabel = prefs.getString("${PREFERENCES_PREFIX}.challengeLabel", ""),
                challengeText = prefs.getString("${PREFERENCES_PREFIX}.challengeText", ""),
                challengeStatus = prefs.getString("${PREFERENCES_PREFIX}.challengeStatus", ""),
                emptyText = prefs.getString("${PREFERENCES_PREFIX}.emptyText", "Open Mulinda to see today"),
            )
        }
    }
}


private fun hwCurrentLocales(context: Context): List<String> {
    val configured = ConfigurationCompat
        .getLocales(context.resources.configuration)
    val tags = mutableListOf<String>()
    for (index in 0 until configured.size()) {
        val locale = configured[index] ?: continue
        val tag = locale.toLanguageTag()
        if (tag.isNotEmpty() && tag != "und") tags.add(tag)
    }
    if (tags.isEmpty()) {
        val fallback = Locale.getDefault().toLanguageTag()
        if (fallback.isNotEmpty() && fallback != "und") tags.add(fallback)
    }
    return tags
}
