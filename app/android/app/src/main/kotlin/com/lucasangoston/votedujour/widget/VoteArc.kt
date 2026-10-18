package com.lucasangoston.votedujour.widget

/** Couleur d'une portion de l'arc ; la teinte claire ou sombre est choisie au rendu. */
enum class ArcColor {
  POUR,
  ABSTENTION,
  CONTRE;

  companion object {
    /** Couleur du résultat : pour (adopté) ou contre (rejeté). */
    fun of(result: VoteResult): ArcColor =
        when (result) {
          VoteResult.ADOPTE -> POUR
          VoteResult.REJETE -> CONTRE
        }
  }
}

/**
 * Calque de l'arc : la portion du demi-cercle entre [start] et 1 (fractions de 0, extrémité gauche,
 * à 1, extrémité droite). Les calques se superposent dans l'ordre : chacun recouvre la fin du
 * précédent, sans jour entre deux couleurs.
 */
data class ArcLayer(val color: ArcColor, val start: Double)

/**
 * Arc du vote, signature de la charte « Hémicycle » (#29). Logique pure, dessinée par
 * [VoteArcRenderer] :
 * - scrutin avec décompte : demi-cercle rempli de gauche à droite, pour puis abstentions puis
 *   contre, proportionnellement à pour + contre + abstentions ;
 * - vote à main levée : pointillés ronds couleur du résultat ;
 * - sans décompte : arc plein couleur du résultat.
 */
sealed interface VoteArc {
  /** Portions pleines, du fond vers le dessus. */
  data class Segmented(val layers: List<ArcLayer>) : VoteArc

  /** Arc plein d'une seule couleur (pas de décompte). */
  data class Solid(val color: ArcColor) : VoteArc

  /** Pointillés ronds d'une seule couleur (vote à main levée). */
  data class Dotted(val color: ArcColor) : VoteArc

  companion object {
    fun of(result: VoteResult, count: VoteCount?, mainLevee: Boolean): VoteArc {
      val color = ArcColor.of(result)
      if (mainLevee) return Dotted(color)
      val total = count?.total ?: 0L
      if (count == null || total <= 0L) return Solid(color)
      var start = 0.0
      val layers = buildList {
        for ((arcColor, value) in
            listOf(
                ArcColor.POUR to count.pour,
                ArcColor.ABSTENTION to count.abstentions,
                ArcColor.CONTRE to count.contre,
            )) {
          if (value <= 0) continue
          add(ArcLayer(arcColor, start))
          start += value.toDouble() / total
        }
      }
      return Segmented(layers)
    }

    /**
     * Positions des points d'un arc en pointillés, en fractions de 0 à 1, régulièrement espacées
     * et avec un point à chaque extrémité.
     */
    fun dotPositions(count: Int): List<Double> =
        when {
          count <= 0 -> emptyList()
          count == 1 -> listOf(0.5)
          else -> (0 until count).map { it.toDouble() / (count - 1) }
        }
  }
}
