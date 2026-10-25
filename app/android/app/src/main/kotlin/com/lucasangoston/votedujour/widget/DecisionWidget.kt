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
import androidx.glance.LocalContext
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
import androidx.glance.layout.fillMaxHeight
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
 * Couleurs de la charte (DESIGN.md, système inspiré de Wired), clair / sombre, en un seul endroit :
 * l'interface en noir, blanc et gris, la couleur aux seules données (vote, résultat). Les aperçus du
 * sélecteur reprennent les mêmes valeurs (`values/widget_colors.xml`,
 * `values-night/widget_colors.xml`).
 */
private object WidgetColors {
  /** Fond du widget : la surface douce de l'app. */
  val surface = ColorProvider(day = Color(0xFFF5F5F5), night = Color(0xFF121212))
  /** Bande du prochain vote du grand widget. */
  val raised = ColorProvider(day = Color(0xFFEBEBEB), night = Color(0xFF1F1F1F))
  val ink = ColorProvider(day = Color(0xFF000000), night = Color(0xFFFFFFFF))
  val ink2 = ColorProvider(day = Color(0xFF6B6B6B), night = Color(0xFF9E9E9E))
  val rule = ColorProvider(day = Color(0xFFE0E0E0), night = Color(0xFF2A2A2A))
  /** Texte du résultat et des chiffres du décompte (inchangés). */
  val pour = ColorProvider(day = Color(0xFF1D6B54), night = Color(0xFF4FB08F))
  val contre = ColorProvider(day = Color(0xFFB4472B), night = Color(0xFFE07A58))

  /**
   * Couleurs du vote (revue UI/UX, #78) : sièges, arc et symboles du décompte. Pour foncé et contre
   * clair de jour, l'inverse de nuit, abstention en gris moyen : distincts en deutéranopie
   * simulée, à 3:1 au moins contre la surface.
   */
  val votePour = ColorProvider(day = Color(0xFF1D6B54), night = Color(0xFF4FB08F))
  val voteContre = ColorProvider(day = Color(0xFFE0683A), night = Color(0xFFB5461F))
  val voteAbstention = ColorProvider(day = Color(0xFF848B91), night = Color(0xFF9AA2AB))

  /** Sièges absents et non-votants (estompés à 28 % par le masque). */
  val seatOff = ColorProvider(day = Color(0xFFAEB4BB), night = Color(0xFF4A5058))

  fun of(color: ArcColor): GlanceColor =
      when (color) {
        ArcColor.POUR -> votePour
        ArcColor.ABSTENTION -> voteAbstention
        ArcColor.CONTRE -> voteContre
      }

  fun of(kind: SeatKind): GlanceColor =
      when (kind) {
        SeatKind.POUR -> votePour
        SeatKind.CONTRE -> voteContre
        SeatKind.ABSTENTION -> voteAbstention
        SeatKind.OFF -> seatOff
      }

  /** « Adopté » couleur pour, « Rejeté » couleur contre. */
  fun of(result: VoteResult): GlanceColor =
      when (result) {
        VoteResult.ADOPTE -> pour
        VoteResult.REJETE -> contre
      }
}

/**
 * Typographie des widgets, en un seul endroit (#78) : familles, graisses et tailles des titres.
 * Glance n'a que les polices du système : serif à la place de Newsreader (affichage en graisse
 * normale, DESIGN.md), sans-serif à la place de Geist. Le cadre garde la forme du système
 * (`R.dimen.decision_widget_radius`).
 */
private object WidgetType {
  /** Mot du résultat (« Adopté ») : petit et moyen, grand. */
  val resultSize = 20.sp
  val largeResultSize = 24.sp
  /** Titres courts : petit widget (sans-serif), moyen et grand (serif). */
  val smallTitleSize = 14.sp
  val mediumTitleSize = 19.sp
  val largeTitleSize = 22.sp
  /** Jour du prochain vote : petit et moyen, bande du grand. */
  val daySize = 40.sp
  val bandDaySize = 30.sp
  val metaSize = 13.sp
  val monthSize = 12.sp

  /** Rétrécissement toléré des titres aux grandes tailles de texte (comme minimumScaleFactor). */
  const val MINIMUM_SCALE = 0.8f

  /**
   * [size] légèrement réduit quand le texte du téléphone est agrandi : il grandit encore, mais
   * moins, pour garder les lignes du titre.
   */
  fun shrunk(context: Context, size: TextUnit): TextUnit =
      size * (1f / context.resources.configuration.fontScale).coerceIn(MINIMUM_SCALE, 1f)

  /** Mot du résultat et titres des widgets moyen et grand. */
  fun display(color: GlanceColor, size: TextUnit) =
      TextStyle(
          color = color,
          fontSize = size,
          fontWeight = FontWeight.Normal,
          fontFamily = FontFamily.Serif,
      )

  /** Jour du prochain vote. */
  fun day(size: TextUnit) =
      TextStyle(color = WidgetColors.ink, fontSize = size, fontFamily = FontFamily.Serif)

  /** Titre court du petit widget et de la bande du prochain vote. */
  fun title(size: TextUnit, bold: Boolean = false) =
      TextStyle(
          color = WidgetColors.ink,
          fontSize = size,
          fontWeight = if (bold) FontWeight.Bold else FontWeight.Medium,
      )

  /** Lignes secondaires. */
  fun meta(size: TextUnit = metaSize, color: GlanceColor = WidgetColors.ink2) =
      TextStyle(color = color, fontSize = size)

  /** Chiffre du décompte, après le symbole du vote. */
  fun tally(color: GlanceColor) =
      TextStyle(color = color, fontSize = metaSize, fontWeight = FontWeight.Medium)
}

/** Marge des widgets (maquette : 14 ; 18 pour le grand). */
private val PADDING = 14.dp
private val LARGE_PADDING = 18.dp

/**
 * Socle des trois widgets (petit, moyen, grand) : même instantané, mêmes couleurs ; seule la mise
 * en page change. Chaque taille a son propre récepteur, pour apparaître séparément dans le
 * sélecteur de widgets.
 */
abstract class BaseDecisionWidget : GlanceAppWidget() {

  override val stateDefinition = HomeWidgetGlanceStateDefinition()

  // Taille exacte : l'hémicycle et le nombre de lignes s'adaptent à la place disponible.
  override val sizeMode: SizeMode = SizeMode.Exact

  override suspend fun provideGlance(context: Context, id: GlanceId) {
    provideContent {
      val preferences = currentState<HomeWidgetGlanceState>().preferences
      val snapshot =
          DecisionSnapshot.parse(preferences.getString(DecisionSnapshot.STORAGE_KEY, null))
      val decision = snapshot?.decisions?.firstOrNull()
      // Calculé à chaque rendu : le worker redessine le widget juste après minuit (#56).
      val upcoming = snapshot?.upcomingVote()
      val next = snapshot?.let { UpcomingVote.shown(it.upcomingVotes, null) }
      Box(
          modifier =
              GlanceModifier.fillMaxSize()
                  .appWidgetBackground()
                  .background(WidgetColors.surface)
                  .cornerRadius(R.dimen.decision_widget_radius)
                  .clickable(actionStartActivity<MainActivity>(context, tapUri(decision, upcoming))),
          contentAlignment = Alignment.TopStart,
      ) {
        when {
          // Sans décision récente, le petit et le moyen widget annoncent le prochain vote
          // solennel ; le grand le met dans sa bande du bas.
          upcoming != null && !upcomingInBand -> UpcomingContent(upcoming)
          decision == null -> EmptyContent()
          else -> Content(context, decision, next)
        }
      }
    }
  }

  /** Place disponible dans le widget, marges [PADDING] déduites. */
  @Composable protected fun contentWidth(): Dp = LocalSize.current.width - PADDING * 2

  @Composable protected fun contentHeight(): Dp = LocalSize.current.height - PADDING * 2

  /**
   * Lien d'un tap hors de la bande : le détail de la dernière décision, ou la liste quand le widget
   * annonce le prochain vote.
   */
  private fun tapUri(decision: WidgetDecision?, upcoming: UpcomingVote?): Uri =
      decision?.takeIf { upcoming == null || upcomingInBand }?.let(::detailUri) ?: LIST_URI

  /** Le prochain vote va dans la bande du bas (grand widget) au lieu de remplacer la décision. */
  protected open val upcomingInBand = false

  /** La dernière décision ; [next] : le prochain vote pas encore passé, s'il y en a un. */
  @Composable
  protected abstract fun Content(context: Context, decision: WidgetDecision, next: UpcomingVote?)

  /** Annonce du prochain vote solennel, à la place de la dernière décision (#56). */
  @Composable protected open fun UpcomingContent(vote: UpcomingVote) {}
}

/** Moyen : hémicycle et décompte à gauche ; résultat, titre court et date à droite. */
class DecisionWidget : BaseDecisionWidget() {
  /** L'arc vide et le jour à gauche ; « Vote · mar. 15 h » et le titre court à droite. */
  @Composable
  override fun UpcomingContent(vote: UpcomingVote) {
    val context = LocalContext.current
    val column = contentWidth() * 0.46f
    Row(
        modifier =
            GlanceModifier.fillMaxSize().padding(PADDING).semantics {
              contentDescription = vote.accessibilityLabel
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
      UpcomingFigure(vote, column, contentHeight())
      Spacer(GlanceModifier.width(14.dp))
      Column(modifier = GlanceModifier.defaultWeight()) {
        Text(vote.whenLabel, style = WidgetType.meta(), maxLines = 1)
        Spacer(GlanceModifier.height(4.dp))
        Text(
            vote.title,
            style =
                WidgetType.display(
                    WidgetColors.ink, WidgetType.shrunk(context, WidgetType.mediumTitleSize)),
            maxLines = 3,
        )
      }
    }
  }

  @Composable
  override fun Content(context: Context, decision: WidgetDecision, next: UpcomingVote?) {
    val column = contentWidth() * 0.46f
    // Hauteur du décompte (environ 24 dp) sous l'hémicycle.
    val figure = minOf(column, (contentHeight() - 24.dp) * HemicycleRenderer.ASPECT)
    Row(
        modifier =
            GlanceModifier.fillMaxSize().padding(PADDING).semantics {
              contentDescription = decision.accessibilityLabel
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
      Column(
          modifier = GlanceModifier.width(column),
          horizontalAlignment = Alignment.CenterHorizontally,
          verticalAlignment = Alignment.CenterVertically,
      ) {
        HemicycleImage(context, decision, figure)
        Spacer(GlanceModifier.height(8.dp))
        CountLine(decision)
      }
      Spacer(GlanceModifier.width(14.dp))
      Column(modifier = GlanceModifier.fillMaxHeight().defaultWeight()) {
        ResultLine(decision, WidgetType.resultSize, withCount = true)
        Spacer(GlanceModifier.height(4.dp))
        Text(
            decision.title,
            style =
                WidgetType.display(
                    WidgetColors.ink, WidgetType.shrunk(context, WidgetType.mediumTitleSize)),
            maxLines = 3,
        )
        Spacer(GlanceModifier.defaultWeight())
        Text(decision.shortDateLabel, style = WidgetType.meta(), maxLines = 1)
      }
    }
  }
}

/** Petit : hémicycle, « Adopté » / « Rejeté », titre court sur deux lignes. */
class SmallDecisionWidget : BaseDecisionWidget() {
  /** Arc vide, jour en grand et mois, « Vote · mar. 15 h », titre court. */
  @Composable
  override fun UpcomingContent(vote: UpcomingVote) {
    val context = LocalContext.current
    Column(
        modifier =
            GlanceModifier.fillMaxSize().padding(PADDING).semantics {
              contentDescription = vote.accessibilityLabel
            }
    ) {
      // Sous la figure : « Vote · … » et deux lignes de titre (environ 64 dp).
      UpcomingFigure(vote, contentWidth(), contentHeight() - 64.dp)
      Spacer(GlanceModifier.height(8.dp))
      Text(vote.whenLabel, style = WidgetType.meta(), maxLines = 1)
      Spacer(GlanceModifier.height(2.dp))
      Text(
          vote.title,
          style = WidgetType.title(WidgetType.shrunk(context, WidgetType.smallTitleSize)),
          maxLines = 2,
      )
    }
  }

  @Composable
  override fun Content(context: Context, decision: WidgetDecision, next: UpcomingVote?) {
    // Sous l'hémicycle : le résultat et deux lignes de titre (environ 68 dp).
    val figure = minOf(contentWidth(), (contentHeight() - 68.dp) * HemicycleRenderer.ASPECT)
    Column(
        modifier =
            GlanceModifier.fillMaxSize().padding(PADDING).semantics {
              contentDescription = decision.accessibilityLabel
            }
    ) {
      HemicycleImage(context, decision, figure)
      Spacer(GlanceModifier.defaultWeight())
      ResultLine(decision, WidgetType.resultSize)
      Spacer(GlanceModifier.height(2.dp))
      Text(
          decision.title,
          style = WidgetType.title(WidgetType.shrunk(context, WidgetType.smallTitleSize)),
          maxLines = 2,
      )
    }
  }
}

/**
 * Grand : la dernière décision en grand (hémicycle, résultat, décompte, titre court), puis la bande
 * du prochain vote, qui ouvre la liste.
 */
class LargeDecisionWidget : BaseDecisionWidget() {
  override val upcomingInBand = true

  @Composable
  override fun Content(context: Context, decision: WidgetDecision, next: UpcomingVote?) {
    val size = LocalSize.current
    val width = size.width - LARGE_PADDING * 2
    // Sous l'hémicycle : résultat, deux lignes de titre (environ 100 dp), et la bande (64 dp).
    val available = size.height - LARGE_PADDING * 2 - 100.dp - (if (next != null) 64.dp else 0.dp)
    val figure = minOf(width, available * HemicycleRenderer.ASPECT)
    Column(modifier = GlanceModifier.fillMaxSize()) {
      Column(
          modifier =
              GlanceModifier.fillMaxWidth()
                  .defaultWeight()
                  .padding(
                      start = LARGE_PADDING,
                      end = LARGE_PADDING,
                      top = LARGE_PADDING,
                      bottom = if (next != null) 12.dp else LARGE_PADDING,
                  )
                  .semantics { contentDescription = decision.accessibilityLabel },
          horizontalAlignment = Alignment.CenterHorizontally,
      ) {
        HemicycleImage(context, decision, figure)
        Spacer(GlanceModifier.defaultWeight())
        Row(
            modifier = GlanceModifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
          ResultLine(decision, WidgetType.largeResultSize, withCount = true)
          Spacer(GlanceModifier.defaultWeight())
          CountLine(decision)
        }
        Spacer(GlanceModifier.height(6.dp))
        Text(
            decision.title,
            style =
                WidgetType.display(
                    WidgetColors.ink, WidgetType.shrunk(context, WidgetType.largeTitleSize)),
            maxLines = 2,
            modifier = GlanceModifier.fillMaxWidth(),
        )
      }
      next?.let { NextVoteBand(context, it) }
    }
  }

  /** Le jour et le mois, le titre court et « Vote · mar. 15 h ». */
  @Composable
  private fun NextVoteBand(context: Context, vote: UpcomingVote) {
    Row(
        modifier =
            GlanceModifier.fillMaxWidth()
                .background(WidgetColors.raised)
                .padding(start = LARGE_PADDING, end = LARGE_PADDING, top = 12.dp, bottom = 14.dp)
                .clickable(actionStartActivity<MainActivity>(context, LIST_URI))
                .semantics { contentDescription = vote.accessibilityLabel },
        verticalAlignment = Alignment.CenterVertically,
    ) {
      Column(
          modifier = GlanceModifier.width(40.dp),
          horizontalAlignment = Alignment.CenterHorizontally,
      ) {
        Text(vote.dayOfMonthLabel, style = WidgetType.day(WidgetType.bandDaySize), maxLines = 1)
        // À l'encre : le gris secondaire ne tient pas 4,5:1 sur la bande.
        Text(
            vote.monthLabel,
            style = WidgetType.meta(WidgetType.monthSize, WidgetColors.ink),
            maxLines = 1,
        )
      }
      Spacer(GlanceModifier.width(14.dp))
      Column(modifier = GlanceModifier.defaultWeight()) {
        Text(vote.title, style = WidgetType.title(15.sp, bold = true), maxLines = 1)
        Text(vote.whenLabel, style = WidgetType.meta(color = WidgetColors.ink), maxLines = 1)
      }
    }
  }
}

/**
 * Hémicycle de [width] de large : les sièges colorés par le vote, un masque par apparence,
 * superposés et teintés en jour / nuit (Android 12+ choisit la teinte au moment de l'affichage,
 * sans redessiner le widget). Sans sièges, l'arc du vote, à la même largeur.
 */
@Composable
private fun HemicycleImage(context: Context, decision: WidgetDecision, width: Dp) {
  val seats = decision.seats
  if (seats == null) {
    ArcImage(context, decision, ArcStyle(width.value.coerceAtLeast(24f), stroke = 16f))
    return
  }
  val size = GlanceModifier.size(width, width / HemicycleRenderer.ASPECT)
  Box(modifier = size) {
    HemicycleRenderer.layers(context, HemicycleLayout.of(seats), width.value).forEach { (kind, mask) ->
      Image(
          provider = ImageProvider(mask),
          // Décrit par le widget (WidgetDecision.accessibilityLabel).
          contentDescription = null,
          modifier = size,
          contentScale = ContentScale.FillBounds,
          colorFilter = ColorFilter.tint(WidgetColors.of(kind)),
      )
    }
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
          // Décrit par le widget (WidgetDecision.accessibilityLabel).
          contentDescription = null,
          modifier = size,
          contentScale = ContentScale.FillBounds,
          colorFilter = ColorFilter.tint(WidgetColors.of(color)),
      )
    }
  }
}

/** Arc vide (couleur filet), le jour en grand et le mois au pied, dans [width] × [maxHeight]. */
@Composable
private fun UpcomingFigure(vote: UpcomingVote, width: Dp, maxHeight: Dp) {
  // Maquette : arc de 300 × 162.
  val arcWidth = minOf(width, maxHeight * (300f / 162f)).coerceAtLeast(48.dp)
  val arcHeight = arcWidth * (162f / 300f)
  Box(
      modifier = GlanceModifier.size(width, arcHeight + 4.dp),
      contentAlignment = Alignment.BottomCenter,
  ) {
    Box(modifier = GlanceModifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
      Image(
          provider = ImageProvider(R.drawable.widget_empty_arc),
          contentDescription = null,
          modifier = GlanceModifier.size(arcWidth, arcHeight),
          contentScale = ContentScale.FillBounds,
          colorFilter = ColorFilter.tint(WidgetColors.rule),
      )
    }
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
      Text(vote.dayOfMonthLabel, style = WidgetType.day(WidgetType.daySize), maxLines = 1)
      Text(vote.monthLabel, style = WidgetType.meta(WidgetType.monthSize), maxLines = 1)
    }
  }
}

/**
 * Mot du résultat, couleur du vote gagnant, suivi des mentions (« provisoire », « à main levée »).
 * Sous un décompte ([withCount]), « à main levée » y est déjà.
 */
@Composable
private fun ResultLine(decision: WidgetDecision, size: TextUnit, withCount: Boolean = false) {
  val mentions =
      decision.mentions.filterNot { withCount && it == WidgetDecision.MAIN_LEVEE_MENTION }
  Row(verticalAlignment = Alignment.Bottom) {
    Text(
        WidgetText.result(decision.result),
        style = WidgetType.display(WidgetColors.of(decision.result), size),
        maxLines = 1,
    )
    if (mentions.isNotEmpty()) {
      Spacer(GlanceModifier.width(6.dp))
      Text(
          mentions.joinToString(" · "),
          style = WidgetType.meta(11.5.sp),
          maxLines = 1,
          modifier = GlanceModifier.padding(bottom = 3.dp),
      )
    }
  }
}

/**
 * Décompte sans mots : la forme dit le vote (rond plein pour, anneau contre, petit point
 * abstention), dans la couleur du vote ; le chiffre suit, dans la couleur de texte habituelle. « À
 * main levée » sans scrutin public.
 */
@Composable
private fun CountLine(decision: WidgetDecision) {
  if (decision.isMainLevee) {
    Text("À main levée", style = WidgetType.meta(), maxLines = 1)
    return
  }
  val count = decision.count ?: return
  Row(verticalAlignment = Alignment.CenterVertically) {
    TallyItem(R.drawable.widget_glyph_pour, WidgetColors.votePour, count.pour, WidgetColors.pour)
    Spacer(GlanceModifier.width(10.dp))
    TallyItem(R.drawable.widget_glyph_contre, WidgetColors.voteContre, count.contre, WidgetColors.contre)
    Spacer(GlanceModifier.width(10.dp))
    TallyItem(
        R.drawable.widget_glyph_abstention,
        WidgetColors.voteAbstention,
        count.abstentions,
        WidgetColors.ink2,
    )
  }
}

@Composable
private fun TallyItem(glyph: Int, glyphColor: GlanceColor, n: Int, color: GlanceColor) {
  Row(verticalAlignment = Alignment.CenterVertically) {
    Image(
        provider = ImageProvider(glyph),
        contentDescription = null,
        modifier = GlanceModifier.size(12.dp),
        colorFilter = ColorFilter.tint(glyphColor),
    )
    Spacer(GlanceModifier.width(4.dp))
    Text(
        n.toString(),
        style = WidgetType.tally(color),
        maxLines = 1,
    )
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

@Composable
private fun EmptyContent() {
  Column(modifier = GlanceModifier.padding(PADDING)) {
    Logo(GlanceModifier.size(33.dp, 18.dp))
    Spacer(GlanceModifier.height(10.dp))
    Text("Décisions de l'Assemblée", style = WidgetType.title(15.sp))
    Spacer(GlanceModifier.height(4.dp))
    Text("Ouvrez l'app pour charger la dernière décision.", style = WidgetType.meta(12.sp))
  }
}

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
