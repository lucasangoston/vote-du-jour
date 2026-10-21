package com.lucasangoston.votedujour.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.text.FontFamily
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider as GlanceColor
import com.lucasangoston.votedujour.MainActivity
import com.lucasangoston.votedujour.R
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver
import es.antonborri.home_widget.actionStartActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/** Lien ouvert par un tap : l'app s'ouvre sur la liste des décisions. */
private val LIST_URI = Uri.parse("votedujour://decisions?homeWidget")

/** Lien ouvert par un tap sur la décision : son écran de détail. */
private fun detailUri(decision: WidgetDecision): Uri =
    Uri.parse("votedujour://decisions/${Uri.encode(decision.id)}?homeWidget")

/**
 * Couleurs de la charte Hémicycle (#29), clair / sombre. Les aperçus du sélecteur reprennent les
 * mêmes valeurs (`values/widget_colors.xml`, `values-night/widget_colors.xml`).
 */
private object WidgetColors {
  val surface = ColorProvider(day = Color(0xFFFFFFFF), night = Color(0xFF191C20))
  val ink = ColorProvider(day = Color(0xFF15181C), night = Color(0xFFECEEF0))
  val ink2 = ColorProvider(day = Color(0xFF4F5761), night = Color(0xFF9AA2AB))
  val rule = ColorProvider(day = Color(0xFFE2E5E8), night = Color(0xFF2A2F35))
  val pour = ColorProvider(day = Color(0xFF1D6B54), night = Color(0xFF4FB08F))
  val contre = ColorProvider(day = Color(0xFFB4472B), night = Color(0xFFE07A58))
  val abstention = ColorProvider(day = Color(0xFFAEB4BB), night = Color(0xFF4A5058))

  fun of(color: ArcColor): GlanceColor =
      when (color) {
        ArcColor.POUR -> pour
        ArcColor.ABSTENTION -> abstention
        ArcColor.CONTRE -> contre
      }

  fun of(result: VoteResult): GlanceColor = of(ArcColor.of(result))
}

/**
 * Socle des trois widgets (petit, moyen, grand) : même instantané, mêmes couleurs, mêmes dates
 * relatives ; seule la mise en page change. Chaque taille a son propre récepteur, pour apparaître
 * séparément dans le sélecteur de widgets.
 */
abstract class BaseDecisionWidget : GlanceAppWidget() {

  override val stateDefinition = HomeWidgetGlanceStateDefinition()

  // Taille exacte : l'arc et le nombre de lignes s'adaptent à la place disponible.
  override val sizeMode: SizeMode = SizeMode.Exact

  /** Nombre de décisions affichées. */
  protected open val decisionCount: Int = 1

  override suspend fun provideGlance(context: Context, id: GlanceId) {
    provideContent {
      val preferences = currentState<HomeWidgetGlanceState>().preferences
      val snapshot =
          DecisionSnapshot.parse(preferences.getString(DecisionSnapshot.STORAGE_KEY, null))
      val decisions = snapshot?.latest(decisionCount).orEmpty()
      // Calculé à chaque rendu : le worker redessine le widget juste après minuit (#56).
      val upcoming = snapshot?.upcomingVote()
      Box(
          modifier =
              GlanceModifier.fillMaxSize()
                  .appWidgetBackground()
                  .background(WidgetColors.surface)
                  .cornerRadius(22.dp)
                  .padding(horizontal = horizontalPadding, vertical = verticalPadding)
                  .clickable(
                      actionStartActivity<MainActivity>(context, tapUri(decisions, upcoming))
                  ),
          contentAlignment = Alignment.TopStart,
      ) {
        when {
          // Sans décision récente, le petit et le moyen widget annoncent le prochain vote
          // solennel ; le grand l'ajoute sous ses décisions.
          upcoming != null && !upcomingBelowDecisions -> UpcomingContent(upcoming)
          decisions.isEmpty() -> EmptyContent()
          else -> Content(context, decisions, upcoming)
        }
      }
    }
  }

  protected open val horizontalPadding = 14.dp
  protected open val verticalPadding = 14.dp

  /** Place disponible dans le widget, marges déduites. */
  @Composable
  protected fun contentWidth(): Dp = LocalSize.current.width - horizontalPadding * 2

  @Composable
  protected fun contentHeight(): Dp = LocalSize.current.height - verticalPadding * 2

  /**
   * Lien d'un tap hors des lignes : par défaut, le détail de la dernière décision, ou la liste
   * quand le widget annonce le prochain vote.
   */
  protected open fun tapUri(decisions: List<WidgetDecision>, upcoming: UpcomingVote?): Uri =
      decisions.firstOrNull()?.takeIf { upcoming == null }?.let(::detailUri) ?: LIST_URI

  /** Le prochain vote s'ajoute sous les décisions (grand widget) au lieu de les remplacer. */
  protected open val upcomingBelowDecisions = false

  @Composable
  protected abstract fun Content(
      context: Context,
      decisions: List<WidgetDecision>,
      upcoming: UpcomingVote?,
  )

  /** Annonce du prochain vote solennel, à la place de la dernière décision (#56). */
  @Composable protected open fun UpcomingContent(vote: UpcomingVote) {}
}

/**
 * Widget moyen : à gauche l'arc, le résultat et le décompte ; à droite l'étape et la date, le
 * titre et l'explication sur deux lignes.
 */
class DecisionWidget : BaseDecisionWidget() {
  override val horizontalPadding = 16.dp

  /** Le jour du vote dans la colonne de l'arc, « Prochain vote solennel » et le titre court. */
  @Composable
  override fun UpcomingContent(vote: UpcomingVote) {
    val roomy = contentWidth() >= 280.dp && contentHeight() >= 100.dp
    Row(
        modifier =
            GlanceModifier.fillMaxSize().semantics {
              contentDescription = WidgetText.upcomingDescription(vote)
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
      Column(
          modifier = GlanceModifier.width(if (roomy) 92.dp else 64.dp),
          horizontalAlignment = Alignment.CenterHorizontally,
      ) {
        Text(vote.weekdayLabel, style = meta(13.sp), maxLines = 1)
        Text(
            vote.dayOfMonthLabel,
            style = titleStyle(if (roomy) 34.sp else 28.sp),
            maxLines = 1,
        )
        Text(vote.monthLabel, style = meta(13.sp), maxLines = 1)
      }
      Spacer(GlanceModifier.width(14.dp))
      Column(modifier = GlanceModifier.defaultWeight()) {
        Text(WidgetText.UPCOMING_KICKER, style = meta(), maxLines = 1)
        Spacer(GlanceModifier.height(5.dp))
        Text(vote.title, style = titleStyle(14.5.sp), maxLines = 3)
      }
    }
  }

  @Composable
  override fun Content(
      context: Context,
      decisions: List<WidgetDecision>,
      upcoming: UpcomingVote?,
  ) {
    val decision = decisions.first()
    // Colonne de la maquette (92 dp) ; plus étroite si le widget est réduit.
    val roomy = contentWidth() >= 280.dp && contentHeight() >= 100.dp
    val columnWidth = if (roomy) 92.dp else 64.dp
    Row(
        modifier =
            GlanceModifier.fillMaxSize().semantics {
              contentDescription = WidgetText.description(decision)
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
      Column(
          modifier = GlanceModifier.width(columnWidth),
          horizontalAlignment = Alignment.CenterHorizontally,
          verticalAlignment = Alignment.CenterVertically,
      ) {
        ArcImage(context, decision, ArcStyle(columnWidth.value, stroke = 14f))
        Spacer(GlanceModifier.height(6.dp))
        ResultText(decision.result, if (roomy) 13.sp else 12.sp)
        decision.count
            ?.takeUnless { decision.isMainLevee }
            ?.let {
              Spacer(GlanceModifier.height(4.dp))
              Text(
                  it.label,
                  style =
                      TextStyle(
                          color = WidgetColors.ink2,
                          fontSize = 10.5.sp,
                          fontFamily = FontFamily.Monospace,
                      ),
                  maxLines = 1,
              )
            }
      }
      Spacer(GlanceModifier.width(14.dp))
      Column(
          modifier = GlanceModifier.defaultWeight(),
          verticalAlignment = Alignment.CenterVertically,
      ) {
        // Calculée à chaque rendu : le worker redessine le widget juste après minuit.
        Text(WidgetText.mediumMeta(decision), style = meta(), maxLines = 1)
        Spacer(GlanceModifier.height(5.dp))
        Text(
            decision.title,
            style = titleStyle(14.5.sp),
            maxLines = if (decision.explanation == null) 4 else 2,
        )
        decision.explanation?.let {
          Spacer(GlanceModifier.height(5.dp))
          Text(it, style = TextStyle(color = WidgetColors.ink2, fontSize = 12.sp), maxLines = 2)
        }
      }
    }
  }
}

/**
 * Petit widget : l'arc et le résultat coloré, le titre, puis la date relative (et les mentions
 * « provisoire » ou « à main levée »).
 */
class SmallDecisionWidget : BaseDecisionWidget() {
  /** « Prochain vote solennel », le jour à la place de l'arc, puis le titre court. */
  @Composable
  override fun UpcomingContent(vote: UpcomingVote) {
    // Lignes de titre (18 dp chacune) sous l'annonce et le jour (~46 dp).
    val titleLines = ((contentHeight() - 52.dp) / 18.dp).toInt().coerceIn(1, 4)
    Column(
        modifier =
            GlanceModifier.fillMaxSize().semantics {
              contentDescription = WidgetText.upcomingDescription(vote)
            }
    ) {
      Text(WidgetText.UPCOMING_KICKER, style = meta(), maxLines = 1)
      Spacer(GlanceModifier.height(2.dp))
      Text(WidgetText.capitalized(vote.dayLabel), style = titleStyle(20.sp), maxLines = 1)
      Spacer(GlanceModifier.defaultWeight())
      Text(vote.title, style = titleStyle(14.sp), maxLines = titleLines)
    }
  }

  @Composable
  override fun Content(
      context: Context,
      decisions: List<WidgetDecision>,
      upcoming: UpcomingVote?,
  ) {
    val decision = decisions.first()
    // Maquette : arc de 58 dp à côté de « Adopté » (~46 dp) ; plus petit si la place manque.
    val arcWidth = (contentWidth() - 48.dp).coerceIn(32.dp, 58.dp)
    // Lignes de titre (18 dp chacune) dans la hauteur restante sous l'arc et au-dessus de la date.
    val titleLines = ((contentHeight() - ArcStyle(arcWidth.value, 16f).heightDp.dp - 30.dp) / 18.dp)
    Column(
        modifier =
            GlanceModifier.fillMaxSize().semantics {
              contentDescription = WidgetText.description(decision)
            }
    ) {
      Row(
          modifier = GlanceModifier.fillMaxWidth(),
          verticalAlignment = Alignment.Bottom,
      ) {
        ArcImage(context, decision, ArcStyle(arcWidth.value, stroke = 16f))
        Spacer(GlanceModifier.defaultWeight())
        ResultText(decision.result, 12.sp)
      }
      Spacer(GlanceModifier.defaultWeight())
      Text(
          decision.title,
          style = titleStyle(14.sp),
          maxLines = titleLines.toInt().coerceIn(1, 4),
      )
      Spacer(GlanceModifier.defaultWeight())
      Text(WidgetText.smallDate(decision), style = meta(), maxLines = 1)
    }
  }
}

/**
 * Grand widget : en-tête (logo et « Dernières décisions »), puis les trois dernières décisions avec
 * leur mini-arc. Chaque ligne ouvre le détail de sa décision ; le reste du widget (en-tête, marges)
 * ouvre la liste.
 */
class LargeDecisionWidget : BaseDecisionWidget() {
  override val decisionCount = LARGE_WIDGET_COUNT
  override val horizontalPadding = 16.dp
  override val verticalPadding = 14.dp

  override fun tapUri(decisions: List<WidgetDecision>, upcoming: UpcomingVote?): Uri = LIST_URI

  override val upcomingBelowDecisions = true

  @Composable
  override fun Content(
      context: Context,
      decisions: List<WidgetDecision>,
      upcoming: UpcomingVote?,
  ) {
    // Glance limite un Column à 10 enfants : en-tête, marge, puis ligne et filet par décision, et
    // la ligne du prochain vote (#56).
    Column(modifier = GlanceModifier.fillMaxSize()) {
      Row(verticalAlignment = Alignment.CenterVertically) {
        Logo(GlanceModifier.size(22.dp, 12.dp))
        Spacer(GlanceModifier.width(8.dp))
        Text(
            "Dernières décisions",
            style =
                TextStyle(color = WidgetColors.ink2, fontSize = 12.sp, fontWeight = FontWeight.Medium),
            maxLines = 1,
        )
      }
      Spacer(GlanceModifier.height(6.dp))
      decisions.forEachIndexed { index, decision ->
        DecisionRow(context, decision, GlanceModifier.defaultWeight())
        if (index < decisions.lastIndex || upcoming != null) {
          Box(GlanceModifier.fillMaxWidth().height(1.dp).background(WidgetColors.rule)) {}
        }
      }
      // Hors des liens des décisions : le tap ouvre la liste.
      upcoming?.let { UpcomingRow(it, GlanceModifier.defaultWeight()) }
    }
  }

  /** Le jour à la place de l'arc, le titre court, puis « Prochain vote solennel · mar. 27 oct. ». */
  @Composable
  private fun UpcomingRow(vote: UpcomingVote, modifier: GlanceModifier) {
    Row(
        modifier =
            modifier.fillMaxWidth().semantics {
              contentDescription = WidgetText.upcomingDescription(vote)
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
      Column(
          modifier = GlanceModifier.width(48.dp),
          horizontalAlignment = Alignment.CenterHorizontally,
      ) {
        Text(vote.dayOfMonthLabel, style = titleStyle(17.sp), maxLines = 1)
        Text(vote.monthLabel, style = meta(11.sp), maxLines = 1)
      }
      Spacer(GlanceModifier.width(12.dp))
      Column(modifier = GlanceModifier.defaultWeight()) {
        Text(vote.title, style = titleStyle(14.sp), maxLines = 2)
        Spacer(GlanceModifier.height(3.dp))
        Text(WidgetText.largeUpcomingMeta(vote), style = meta(), maxLines = 1)
      }
    }
  }

  @Composable
  private fun DecisionRow(context: Context, decision: WidgetDecision, modifier: GlanceModifier) {
    Row(
        modifier =
            modifier
                .fillMaxWidth()
                .clickable(actionStartActivity<MainActivity>(context, detailUri(decision)))
                .semantics { contentDescription = WidgetText.description(decision) },
        verticalAlignment = Alignment.CenterVertically,
    ) {
      ArcImage(context, decision, ArcStyle(48f, stroke = 16f))
      Spacer(GlanceModifier.width(12.dp))
      Column(modifier = GlanceModifier.defaultWeight()) {
        Text(decision.title, style = titleStyle(14.sp), maxLines = 2)
        Spacer(GlanceModifier.height(3.dp))
        // Sur la ligne du résultat : « provisoire » ou « à main levée » restent visibles.
        Row(verticalAlignment = Alignment.CenterVertically) {
          ResultText(decision.result, 11.5.sp)
          Text(WidgetText.largeMeta(decision), style = meta(), maxLines = 1)
        }
      }
    }
  }

  companion object {
    /** Nombre de décisions du grand widget. */
    const val LARGE_WIDGET_COUNT = 3
  }
}

/**
 * Arc du vote : un masque par couleur, superposés et teintés en jour / nuit (Android 12+ choisit la
 * teinte au moment de l'affichage, sans redessiner le widget).
 */
@Composable
private fun ArcImage(context: Context, decision: WidgetDecision, style: ArcStyle) {
  val size = GlanceModifier.size(style.widthDp.dp, style.heightDp.dp)
  Box(modifier = size) {
    VoteArcRenderer.layers(context, decision.arc, style).forEach { (color, bitmap) ->
      Image(
          provider = ImageProvider(bitmap),
          // Décrit par la ligne ou le widget (WidgetText.description).
          contentDescription = null,
          modifier = size,
          contentScale = ContentScale.FillBounds,
          colorFilter = ColorFilter.tint(WidgetColors.of(color)),
      )
    }
  }
}

/**
 * Logo Perchoir (hémicycle en bandes) : deux calques superposés, arcs couleur encre et demi-disque
 * couleur pour, teintés en jour / nuit comme l'arc du vote.
 */
@Composable
private fun Logo(modifier: GlanceModifier) {
  Box(modifier = modifier) {
    Image(
        provider = ImageProvider(R.drawable.ic_perchoir_arcs),
        contentDescription = null,
        modifier = modifier,
        colorFilter = ColorFilter.tint(WidgetColors.ink),
    )
    Image(
        provider = ImageProvider(R.drawable.ic_perchoir_seat),
        contentDescription = null,
        modifier = modifier,
        colorFilter = ColorFilter.tint(WidgetColors.pour),
    )
  }
}

/** « Adopté » / « Rejeté », mot coloré sans pastille. */
@Composable
private fun ResultText(result: VoteResult, size: TextUnit) {
  Text(
      WidgetText.result(result),
      style = TextStyle(color = WidgetColors.of(result), fontSize = size, fontWeight = FontWeight.Bold),
      maxLines = 1,
  )
}

@Composable
private fun EmptyContent() {
  Column {
    Logo(GlanceModifier.size(33.dp, 18.dp))
    Spacer(GlanceModifier.height(10.dp))
    Text("Décisions de l'Assemblée", style = titleStyle(15.sp))
    Spacer(GlanceModifier.height(4.dp))
    Text("Ouvrez l'app pour charger la dernière décision.", style = meta(12.sp))
  }
}

/** Titres : police système en graisse moyenne (Glance n'a pas de demi-gras ni Geist). */
private fun titleStyle(size: TextUnit) =
    TextStyle(color = WidgetColors.ink, fontSize = size, fontWeight = FontWeight.Medium)

private fun meta(size: TextUnit = 11.5.sp) = TextStyle(color = WidgetColors.ink2, fontSize = size)

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
    // Pas de super.onUpdate : celui de home_widget attend la mise à jour Glance dans un runBlocking
    // sur le thread principal, alors que Glance démarre sa session (SessionWorker) sur ce même
    // thread. Le récepteur restait bloqué jusqu'à l'ANR et le widget n'était pas redessiné. Même
    // travail (rafraîchir l'état puis redessiner), mais hors du thread principal.
    val pending = goAsync()
    CoroutineScope(Dispatchers.Default).launch {
      try {
        val manager = GlanceAppWidgetManager(context)
        appWidgetIds.forEach { appWidgetId ->
          val id = manager.getGlanceIdBy(appWidgetId)
          updateAppWidgetState(context, HomeWidgetGlanceStateDefinition(), id) { it }
          glanceAppWidget.update(context, id)
        }
      } catch (e: Exception) {
        Log.w("DecisionWidget", "Mise à jour du widget impossible : $e")
      } finally {
        pending.finish()
      }
    }
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
