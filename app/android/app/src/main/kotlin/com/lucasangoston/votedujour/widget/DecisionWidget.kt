package com.lucasangoston.votedujour.widget

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.defaultWeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.lucasangoston.votedujour.MainActivity
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver
import es.antonborri.home_widget.actionStartActivity

/** Lien ouvert par un tap : l'app s'ouvre sur la liste des décisions. */
private val LIST_URI = Uri.parse("votedujour://decisions?homeWidget")

/** Palette neutre (pas de couleur de parti), clair / sombre. */
private object WidgetColors {
  val background = ColorProvider(day = Color(0xFFFFFFFF), night = Color(0xFF1E1E1E))
  val primary = ColorProvider(day = Color(0xFF1B1B1B), night = Color(0xFFEDEDED))
  val secondary = ColorProvider(day = Color(0xFF5E5E5E), night = Color(0xFFABABAB))
  val onBadge = ColorProvider(day = Color.White, night = Color.White)

  // Mêmes teintes que les badges de l'app (`ResultColors` dans `theme.dart`).
  val adopted = ColorProvider(day = Color(0xFF2E7D32), night = Color(0xFF2E7D32))
  val rejected = ColorProvider(day = Color(0xFFB23B1E), night = Color(0xFFB23B1E))
}

/** Widget moyen : la dernière décision, son résultat et sa date. */
class DecisionWidget : GlanceAppWidget() {

  override val stateDefinition = HomeWidgetGlanceStateDefinition()

  override suspend fun provideGlance(context: Context, id: GlanceId) {
    provideContent {
      val preferences = currentState<HomeWidgetGlanceState>().preferences
      val decision =
          DecisionSnapshot.parse(preferences.getString(DecisionSnapshot.STORAGE_KEY, null))
              ?.decisions
              ?.firstOrNull()
      Content(context, decision)
    }
  }

  @Composable
  private fun Content(context: Context, decision: WidgetDecision?) {
    Box(
        modifier =
            GlanceModifier.fillMaxSize()
                .appWidgetBackground()
                .background(WidgetColors.background)
                .cornerRadius(16.dp)
                .padding(16.dp)
                .clickable(actionStartActivity<MainActivity>(context, LIST_URI)),
        contentAlignment = Alignment.TopStart,
    ) {
      if (decision != null) DecisionContent(decision) else EmptyContent()
    }
  }

  @Composable
  private fun DecisionContent(decision: WidgetDecision) {
    Column(modifier = GlanceModifier.fillMaxSize()) {
      Row(
          modifier = GlanceModifier.fillMaxWidth(),
          verticalAlignment = Alignment.CenterVertically,
      ) {
        ResultBadge(decision.result)
        decision.stage?.let {
          Spacer(GlanceModifier.width(8.dp))
          Text(it, style = caption(), maxLines = 1)
        }
        Spacer(GlanceModifier.defaultWeight())
        Text(decision.dateLabel, style = caption(), maxLines = 1)
      }
      Spacer(GlanceModifier.height(8.dp))
      Text(
          decision.title,
          style =
              TextStyle(color = WidgetColors.primary, fontSize = 15.sp, fontWeight = FontWeight.Medium),
          maxLines = if (decision.explanation == null) 4 else 2,
      )
      decision.explanation?.let {
        Spacer(GlanceModifier.height(4.dp))
        Text(it, style = caption(), maxLines = 2)
      }
    }
  }

  @Composable
  private fun ResultBadge(result: VoteResult) {
    val (label, color) =
        when (result) {
          VoteResult.ADOPTE -> "✓ Adopté" to WidgetColors.adopted
          VoteResult.REJETE -> "✕ Rejeté" to WidgetColors.rejected
        }
    Box(
        modifier =
            GlanceModifier.background(color)
                .cornerRadius(6.dp)
                .padding(horizontal = 8.dp, vertical = 3.dp)
    ) {
      Text(
          label,
          style =
              TextStyle(color = WidgetColors.onBadge, fontSize = 12.sp, fontWeight = FontWeight.Bold),
          maxLines = 1,
      )
    }
  }

  @Composable
  private fun EmptyContent() {
    Column {
      Text(
          "Décisions de l'Assemblée",
          style =
              TextStyle(color = WidgetColors.primary, fontSize = 15.sp, fontWeight = FontWeight.Medium),
      )
      Spacer(GlanceModifier.height(4.dp))
      Text("Ouvrez l'app pour charger la dernière décision.", style = caption())
    }
  }

  private fun caption() = TextStyle(color = WidgetColors.secondary, fontSize = 12.sp)
}

class DecisionWidgetReceiver : HomeWidgetGlanceWidgetReceiver<DecisionWidget>() {
  override val glanceAppWidget = DecisionWidget()
}
