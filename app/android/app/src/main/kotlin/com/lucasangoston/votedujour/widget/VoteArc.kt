package com.lucasangoston.votedujour.widget

import org.json.JSONArray
import org.json.JSONObject

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

    /** Sens d'un tronçon de l'arc de l'hémicycle (`pour`, `abstention`, `contre`), ou `null`. */
    fun parse(json: Any?): ArcColor? =
        when (json) {
          "pour" -> POUR
          "abstention" -> ABSTENTION
          "contre" -> CONTRE
          else -> null
        }
  }

  /** Valeur écrite dans l'instantané. */
  val json: String
    get() = name.lowercase()
}

/**
 * Tronçon de l'arc dans l'ordre de l'hémicycle (#67) : `{"position": "pour", "n": 382}`, [n]
 * strictement positif.
 */
data class HemicyclePart(val color: ArcColor, val n: Int) {
  fun toJson(): JSONObject = JSONObject().put("position", color.json).put("n", n)

  companion object {
    /**
     * Arc de gauche à droite, mêmes règles que `HemicycleSegment.tryParseList` : `null` s'il est
     * absent ou vide, ou si un seul tronçon est illisible (sens inconnu, nombre manquant, non
     * entier, nul ou négatif).
     */
    fun parseList(json: JSONArray?): List<HemicyclePart>? {
      if (json == null || json.length() == 0) return null
      return (0 until json.length()).map { i ->
        val item = json.opt(i) as? JSONObject ?: return null
        val color = ArcColor.parse(item.opt("position")) ?: return null
        val n =
            when (val value = item.opt("n")) {
              is Int -> value.toLong()
              is Long -> value
              else -> return null
            }
        if (n <= 0 || n > Int.MAX_VALUE) return null
        HemicyclePart(color, n.toInt())
      }
    }

    fun toJson(parts: List<HemicyclePart>): JSONArray = JSONArray(parts.map { it.toJson() })
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
 * - scrutin avec arc dans l'ordre de l'hémicycle (#67) : ses tronçons de gauche à droite, groupes
 *   de gauche à gauche, proportionnels aux voix ;
 * - scrutin avec décompte seulement (décision provisoire, instantané ancien) : demi-cercle rempli
 *   de gauche à droite, pour puis abstentions puis contre, proportionnellement à pour + contre +
 *   abstentions ;
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
    fun of(
        result: VoteResult,
        count: VoteCount?,
        mainLevee: Boolean,
        hemicycle: List<HemicyclePart>? = null,
    ): VoteArc {
      val color = ArcColor.of(result)
      if (mainLevee) return Dotted(color)
      if (!hemicycle.isNullOrEmpty()) return segmented(hemicycle.map { it.color to it.n })
      if (count == null || count.total <= 0L) return Solid(color)
      return segmented(
          listOf(
              ArcColor.POUR to count.pour,
              ArcColor.ABSTENTION to count.abstentions,
              ArcColor.CONTRE to count.contre,
          ))
    }

    /** Calques proportionnels aux voix, de gauche à droite ; les parts vides sont omises. */
    private fun segmented(parts: List<Pair<ArcColor, Int>>): VoteArc {
      val total = parts.sumOf { it.second.coerceAtLeast(0).toLong() }
      var votes = 0L
      val layers = buildList {
        for ((arcColor, value) in parts) {
          if (value <= 0) continue
          add(ArcLayer(arcColor, votes.toDouble() / total))
          votes += value
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
