package com.lucasangoston.votedujour.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
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
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
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

/** Lien ouvert par un tap sur la décision : son écran de détail. */
private fun detailUri(decision: WidgetDecision): Uri =
    Uri.parse("votedujour://decisions/${Uri.encode(decision.id)}?homeWidget")

/** Palette neutre (pas de couleur de parti), clair / sombre. */
private object WidgetColors {
  val background = ColorProvider(day = Color(0xFFFFFFFF), night = Color(0xFF1E1E1E))
  val primary = ColorProvider(day = Color(0xFF1B1B1B), night = Color(0xFFEDEDED))
  val secondary = ColorProvider(day = Color(0xFF5E5E5E), night = Color(0xFFABABAB))
  val divider = ColorProvider(day = Color(0x1F000000), night = Color(0x29FFFFFF))
  val onBadge = ColorProvider(day = Color.White, night = Color.White)

  // Mêmes teintes que les badges de l'app (`ResultColors` dans `theme.dart`).
  val adopted = ColorProvider(day = Color(0xFF2E7D32), night = Color(0xFF2E7D32))
  val rejected = ColorProvider(day = Color(0xFFB23B1E), night = Color(0xFFB23B1E))
}

/**
 * Socle des trois widgets (petit, moyen, grand) : même instantané, mêmes couleurs, mêmes dates
 * relatives ; seule la mise en page change. Chaque taille a son propre récepteur, pour apparaître
 * séparément dans le sélecteur de widgets.
 */
abstract class BaseDecisionWidget : GlanceAppWidget() {

  override val stateDefinition = HomeWidgetGlanceStateDefinition()

  /** Nombre de décisions affichées. */
  protected open val decisionCount: Int = 1

  override suspend fun provideGlance(context: Context, id: GlanceId) {
    provideContent {
      val preferences = currentState<HomeWidgetGlanceState>().preferences
      val decisions =
          DecisionSnapshot.parse(preferences.getString(DecisionSnapshot.STORAGE_KEY, null))
              ?.latest(decisionCount)
              .orEmpty()
      Box(
          modifier =
              GlanceModifier.fillMaxSize()
                  .appWidgetBackground()
                  .background(WidgetColors.background)
                  .cornerRadius(16.dp)
                  .padding(contentPadding)
                  .clickable(actionStartActivity<MainActivity>(context, tapUri(decisions))),
          contentAlignment = Alignment.TopStart,
      ) {
        if (decisions.isEmpty()) EmptyContent() else Content(context, decisions)
      }
    }
  }

  protected open val contentPadding = 16.dp

  /** Lien d'un tap hors des lignes : par défaut, le détail de la dernière décision. */
  protected open fun tapUri(decisions: List<WidgetDecision>): Uri =
      decisions.firstOrNull()?.let(::detailUri) ?: LIST_URI

  @Composable protected abstract fun Content(context: Context, decisions: List<WidgetDecision>)
}

/** Widget moyen : la dernière décision, son résultat, sa date et son explication. */
class DecisionWidget : BaseDecisionWidget() {
  @Composable
  override fun Content(context: Context, decisions: List<WidgetDecision>) {
    val decision = decisions.first()
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
        // Calculée à chaque rendu : le worker redessine le widget juste après minuit.
        Text(RelativeDate.label(decision.date), style = caption(), maxLines = 1)
      }
      Spacer(GlanceModifier.height(8.dp))
      Text(
          decision.title,
          style = titleStyle(15.sp),
          maxLines = if (decision.explanation == null) 4 else 2,
      )
      decision.explanation?.let {
        Spacer(GlanceModifier.height(4.dp))
        Text(it, style = caption(), maxLines = 2)
      }
    }
  }
}

/**
 * Petit widget : badge, titre court et étape de la dernière décision ; la date relative à côté du
 * badge quand la largeur le permet. Pas d'explication.
 */
class SmallDecisionWidget : BaseDecisionWidget() {
  // Taille exacte : la date n'est affichée que si elle tient à côté du badge.
  override val sizeMode = SizeMode.Exact
  override val contentPadding = 12.dp

  @Composable
  override fun Content(context: Context, decisions: List<WidgetDecision>) {
    val decision = decisions.first()
    val size = LocalSize.current
    Column(modifier = GlanceModifier.fillMaxSize()) {
      Row(
          modifier = GlanceModifier.fillMaxWidth(),
          verticalAlignment = Alignment.CenterVertically,
      ) {
        ResultBadge(decision.result)
        if (showsDateNextToBadge(size)) {
          Spacer(GlanceModifier.defaultWeight())
          Text(RelativeDate.label(decision.date), style = caption(11.sp), maxLines = 1)
        }
      }
      Spacer(GlanceModifier.height(6.dp))
      Text(
          decision.title,
          style = titleStyle(14.sp),
          maxLines = if (size.height < 150.dp) 3 else 4,
          modifier = GlanceModifier.defaultWeight(),
      )
      decision.stage?.let {
        Spacer(GlanceModifier.height(4.dp))
        Text(it, style = caption(11.sp), maxLines = 2)
      }
    }
  }

  /** Le badge (~70 dp) et « Il y a 3 jours » (~75 dp) tiennent côte à côte. */
  private fun showsDateNextToBadge(size: DpSize): Boolean =
      size.width - contentPadding * 2 >= 150.dp
}

/**
 * Grand widget : les trois dernières décisions. Chaque ligne ouvre le détail de sa décision ; le
 * reste du widget (titre, marges) ouvre la liste.
 */
class LargeDecisionWidget : BaseDecisionWidget() {
  override val decisionCount = LARGE_WIDGET_COUNT

  override fun tapUri(decisions: List<WidgetDecision>): Uri = LIST_URI

  @Composable
  override fun Content(context: Context, decisions: List<WidgetDecision>) {
    Column(modifier = GlanceModifier.fillMaxSize()) {
      Text(
          "DERNIÈRES DÉCISIONS",
          style =
              TextStyle(
                  color = WidgetColors.secondary, fontSize = 12.sp, fontWeight = FontWeight.Medium),
          maxLines = 1,
      )
      // Un Column par ligne : Glance limite un Column à 10 enfants.
      decisions.forEachIndexed { index, decision ->
        Column(modifier = GlanceModifier.fillMaxWidth()) {
          Spacer(GlanceModifier.height(if (index == 0) 8.dp else 6.dp))
          if (index > 0) {
            Box(GlanceModifier.fillMaxWidth().height(1.dp).background(WidgetColors.divider)) {}
            Spacer(GlanceModifier.height(6.dp))
          }
          DecisionRow(context, decision)
        }
      }
    }
  }

  @Composable
  private fun DecisionRow(context: Context, decision: WidgetDecision) {
    Column(
        modifier =
            GlanceModifier.fillMaxWidth()
                .padding(vertical = 2.dp)
                .clickable(actionStartActivity<MainActivity>(context, detailUri(decision)))
                .semantics { contentDescription = rowDescription(decision) },
    ) {
      Row(
          modifier = GlanceModifier.fillMaxWidth(),
          verticalAlignment = Alignment.CenterVertically,
      ) {
        ResultBadge(decision.result)
        Spacer(GlanceModifier.defaultWeight())
        Text(RelativeDate.label(decision.date), style = caption(), maxLines = 1)
      }
      Spacer(GlanceModifier.height(4.dp))
      Text(decision.title, style = titleStyle(14.sp), maxLines = 2)
      // Sur sa propre ligne : « provisoire » ou « à main levée » restent visibles.
      decision.stage?.let {
        Spacer(GlanceModifier.height(2.dp))
        Text(it, style = caption(), maxLines = 1)
      }
    }
  }

  private fun rowDescription(decision: WidgetDecision): String =
      listOfNotNull(
              if (decision.result == VoteResult.ADOPTE) "Adopté" else "Rejeté",
              decision.title,
              decision.stage,
              RelativeDate.label(decision.date),
          )
          .joinToString(". ")

  companion object {
    /** Nombre de décisions du grand widget. */
    const val LARGE_WIDGET_COUNT = 3
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
        style = TextStyle(color = WidgetColors.onBadge, fontSize = 12.sp, fontWeight = FontWeight.Bold),
        maxLines = 1,
    )
  }
}

@Composable
private fun EmptyContent() {
  Column {
    Text("Décisions de l'Assemblée", style = titleStyle(15.sp))
    Spacer(GlanceModifier.height(4.dp))
    Text("Ouvrez l'app pour charger la dernière décision.", style = caption())
  }
}

private fun titleStyle(size: androidx.compose.ui.unit.TextUnit) =
    TextStyle(color = WidgetColors.primary, fontSize = size, fontWeight = FontWeight.Medium)

private fun caption(size: androidx.compose.ui.unit.TextUnit = 12.sp) =
    TextStyle(color = WidgetColors.secondary, fontSize = size)

/**
 * Récepteurs des trois tailles. Le rafraîchissement autonome (voir DecisionRefreshWorker.kt) est
 * programmé à l'ajout d'un widget, réarmé à chaque mise à jour système (démarrage, mise à jour de
 * l'app) et annulé quand il ne reste plus aucun widget, toutes tailles confondues.
 */
abstract class BaseDecisionWidgetReceiver<T : GlanceAppWidget> :
    HomeWidgetGlanceWidgetReceiver<T>() {

  override fun onEnabled(context: Context) {
    super.onEnabled(context)
    DecisionRefreshScheduler.schedule(context)
  }

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
  ) {
    super.onUpdate(context, appWidgetManager, appWidgetIds)
    DecisionRefreshScheduler.schedule(context)
  }

  override fun onDisabled(context: Context) {
    super.onDisabled(context)
    if (!DecisionWidgets.anyPlaced(context)) DecisionRefreshScheduler.cancel(context)
  }
}

class SmallDecisionWidgetReceiver : BaseDecisionWidgetReceiver<SmallDecisionWidget>() {
  override val glanceAppWidget = SmallDecisionWidget()
}

class DecisionWidgetReceiver : BaseDecisionWidgetReceiver<DecisionWidget>() {
  override val glanceAppWidget = DecisionWidget()
}

class LargeDecisionWidgetReceiver : BaseDecisionWidgetReceiver<LargeDecisionWidget>() {
  override val glanceAppWidget = LargeDecisionWidget()
}

/** Les trois tailles, pour les redessiner ou savoir s'il en reste une sur l'écran d'accueil. */
object DecisionWidgets {
  val receivers =
      listOf(
          SmallDecisionWidgetReceiver::class.java,
          DecisionWidgetReceiver::class.java,
          LargeDecisionWidgetReceiver::class.java,
      )

  fun all(): List<GlanceAppWidget> =
      listOf(SmallDecisionWidget(), DecisionWidget(), LargeDecisionWidget())

  fun anyPlaced(context: Context): Boolean {
    val manager = AppWidgetManager.getInstance(context)
    return receivers.any { manager.getAppWidgetIds(ComponentName(context, it)).isNotEmpty() }
  }
}
