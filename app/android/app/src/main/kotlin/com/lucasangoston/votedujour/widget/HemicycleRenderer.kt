package com.lucasangoston.votedujour.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * Dessine l'hémicycle d'une décision (#78) en masques : Glance ne sait pas tracer de formes. Un
 * masque par apparence de siège (pour, contre, abstention, estompés), teinté au rendu par une
 * couleur jour / nuit, comme l'arc du vote (voir `HemicycleImage` dans DecisionWidget.kt).
 *
 * Masques `ALPHA_8` (un octet par pixel) et résolution plafonnée : les images d'un widget passent
 * par le binder, limité à environ 1 Mo par mise à jour.
 */
object HemicycleRenderer {
  /** Pixels de l'ensemble des masques d'un hémicycle, au plus. */
  const val PIXEL_BUDGET = 480_000

  /** Pixels par dp, au plus : au-delà, un siège de 3 dp n'y gagne rien. */
  const val MAX_SCALE = 2f

  /** Opacité des sièges estompés (absents, non-votants). */
  const val OFF_ALPHA = 0.28f

  /** Rapport largeur / hauteur du dessin. */
  const val ASPECT = HemicycleGeometry.VIEW_WIDTH / HemicycleGeometry.VIEW_HEIGHT

  /**
   * Pixels par dp des masques d'un dessin de [widthDp] × [heightDp] en [layers] calques : la densité
   * de l'écran, plafonnée à [MAX_SCALE] et au budget [PIXEL_BUDGET].
   */
  fun scale(widthDp: Float, heightDp: Float, layers: Int, density: Float): Float {
    val area = widthDp * heightDp * max(1, layers)
    if (area <= 0f) return density
    return min(min(density, MAX_SCALE), sqrt(PIXEL_BUDGET / area))
  }

  /** Masques à superposer, du fond vers le dessus, avec leur apparence. */
  fun layers(context: Context, layout: HemicycleLayout, widthDp: Float): List<Pair<SeatKind, Bitmap>> {
    val heightDp = widthDp / ASPECT
    val s = scale(widthDp, heightDp, layout.dots.size, context.resources.displayMetrics.density)
    val width = (widthDp * s).roundToInt().coerceAtLeast(1)
    val height = (heightDp * s).roundToInt().coerceAtLeast(1)
    val unit = width / HemicycleGeometry.VIEW_WIDTH
    return layout.dots.map { (kind, points) ->
      val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ALPHA_8)
      val canvas = Canvas(bitmap)
      canvas.scale(unit, unit)
      canvas.translate(-HemicycleGeometry.VIEW_X, -HemicycleGeometry.VIEW_Y)
      val paint =
          Paint(Paint.ANTI_ALIAS_FLAG).apply {
            alpha = if (kind == SeatKind.OFF) (OFF_ALPHA * 255).roundToInt() else 255
          }
      val r = HemicycleGeometry.SEAT_RADIUS * kind.radiusScale
      for (i in points.indices step 2) canvas.drawCircle(points[i], points[i + 1], r, paint)
      kind to bitmap
    }
  }
}
