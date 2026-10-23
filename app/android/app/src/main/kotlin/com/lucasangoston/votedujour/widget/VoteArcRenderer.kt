package com.lucasangoston.votedujour.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Tracé d'un arc dans le repère des maquettes (viewBox 120 x 66, centre 60,60, rayon 50).
 * [stroke] : épaisseur de l'arc plein ; [dotStroke] : diamètre des points (main levée).
 */
data class ArcStyle(val widthDp: Float, val stroke: Float, val dotStroke: Float = 12f) {
  val heightDp: Float
    get() = widthDp * VIEW_HEIGHT / VIEW_WIDTH

  companion object {
    const val VIEW_WIDTH = 120f
    const val VIEW_HEIGHT = 66f
    const val CENTER_X = 60f
    const val CENTER_Y = 60f
    const val RADIUS = 50f

    /** Pointillés de la maquette : un point tous les 19,6 sur un demi-cercle de 157. */
    const val DOT_COUNT = 9
  }
}

/**
 * Dessine les calques de [VoteArc] en Bitmap : Glance ne sait pas tracer de chemins. Un masque
 * blanc par couleur (trois au plus, même pour un arc de l'hémicycle en nombreux tronçons), teinté
 * au rendu par une couleur jour / nuit (le widget suit le mode sombre sans être redessiné, voir
 * `ArcImage` dans DecisionWidget.kt).
 */
object VoteArcRenderer {
  /**
   * Chevauchement d'un tronçon sur le suivant, en fraction du demi-cercle (0,3°) : pas de jour
   * anticrénelé entre deux couleurs.
   */
  private const val OVERLAP = 0.3 / 180

  /** Masques à superposer, du fond vers le dessus, avec leur couleur. */
  fun layers(context: Context, arc: VoteArc, style: ArcStyle): List<Pair<ArcColor, Bitmap>> {
    val density = context.resources.displayMetrics.density
    return when (arc) {
      is VoteArc.Segmented ->
          spans(arc).entries.map { (color, spans) -> color to solid(style, density, spans) }
      is VoteArc.Solid -> listOf(arc.color to solid(style, density, listOf(0.0 to 1.0)))
      is VoteArc.Dotted -> listOf(arc.color to dotted(style, density))
    }
  }

  /**
   * Portions visibles de chaque couleur, de [ArcLayer.start] au début du calque suivant (qui le
   * recouvre), prolongées de [OVERLAP] sous ce calque ; couleurs dans l'ordre d'apparition.
   */
  fun spans(arc: VoteArc.Segmented): Map<ArcColor, List<Pair<Double, Double>>> =
      arc.layers
          .mapIndexed { i, layer ->
            val next = arc.layers.getOrNull(i + 1)?.start
            layer.color to (layer.start to (next?.plus(OVERLAP)?.coerceAtMost(1.0) ?: 1.0))
          }
          .groupBy({ it.first }, { it.second })

  private fun canvas(style: ArcStyle, density: Float): Pair<Bitmap, Canvas> {
    val width = (style.widthDp * density).roundToInt().coerceAtLeast(1)
    val height = (style.heightDp * density).roundToInt().coerceAtLeast(1)
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    canvas.scale(width / ArcStyle.VIEW_WIDTH, height / ArcStyle.VIEW_HEIGHT)
    return bitmap to canvas
  }

  /** Portions pleines [spans] (début, fin), bouts droits. */
  private fun solid(style: ArcStyle, density: Float, spans: List<Pair<Double, Double>>): Bitmap {
    val (bitmap, canvas) = canvas(style, density)
    val paint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
          color = Color.WHITE
          this.style = Paint.Style.STROKE
          strokeWidth = style.stroke
          strokeCap = Paint.Cap.BUTT
        }
    val r = ArcStyle.RADIUS
    val oval =
        RectF(ArcStyle.CENTER_X - r, ArcStyle.CENTER_Y - r, ArcStyle.CENTER_X + r, ArcStyle.CENTER_Y + r)
    for ((start, end) in spans) {
      val from = start.coerceIn(0.0, 1.0).toFloat()
      val to = end.coerceIn(0.0, 1.0).toFloat()
      if (to <= from) continue
      // 180° : extrémité gauche ; le sens horaire passe par le haut.
      canvas.drawArc(oval, 180f + 180f * from, 180f * (to - from), false, paint)
    }
    return bitmap
  }

  /** Pointillés ronds régulièrement espacés, un point à chaque extrémité. */
  private fun dotted(style: ArcStyle, density: Float): Bitmap {
    val (bitmap, canvas) = canvas(style, density)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
    for (position in VoteArc.dotPositions(ArcStyle.DOT_COUNT)) {
      val angle = Math.PI * (1 + position)
      canvas.drawCircle(
          ArcStyle.CENTER_X + ArcStyle.RADIUS * cos(angle).toFloat(),
          ArcStyle.CENTER_Y + ArcStyle.RADIUS * sin(angle).toFloat(),
          style.dotStroke / 2,
          paint,
      )
    }
    return bitmap
  }
}
