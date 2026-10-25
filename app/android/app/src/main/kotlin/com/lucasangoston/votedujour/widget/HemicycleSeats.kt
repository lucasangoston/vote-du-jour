package com.lucasangoston.votedujour.widget

import org.json.JSONArray
import org.json.JSONObject

/**
 * Vote du député assis à une place lors d'un scrutin (#71), codé sur une lettre comme dans le
 * fichier de détail (`HemicycleSeat` du contrat).
 */
enum class SeatVote(val letter: Char) {
  POUR('p'),
  CONTRE('c'),
  ABSTENTION('a'),

  /** Présent sans prendre part au vote. */
  NON_VOTANT('n'),

  /** Pas de vote nominatif. */
  ABSENT('x');

  companion object {
    fun of(letter: Char): SeatVote? = entries.firstOrNull { it.letter == letter }
  }
}

/**
 * Votes de l'hémicycle d'une décision (#78), tels que l'instantané les porte : une chaîne dont le
 * caractère de rang `i` est le vote de la place `i + 1` (lettre de [SeatVote]), `-` pour une place
 * sans député. `"pp-ca"` : places 1 et 2 pour, 4 contre, 5 abstention.
 *
 * Les widgets colorent chaque siège par son vote, pas par son groupe : à 2 px, la forme d'un siège
 * ne se lit plus.
 */
data class SeatVotes(val byPlace: Map<Int, SeatVote>) {
  /** Forme écrite dans l'instantané. */
  val encoded: String
    get() {
      val last = byPlace.keys.maxOrNull() ?: 0
      return (1..last.coerceAtLeast(1))
          .map { byPlace[it]?.letter ?: EMPTY_PLACE }
          .joinToString("")
    }

  companion object {
    /** Garde-fou : bien plus que les 650 numéros de place du plan. */
    const val MAX_PLACES = 1000
    const val EMPTY_PLACE = '-'

    /**
     * Lit la chaîne de l'instantané ; `null` si elle est absente, vide, trop longue, ne compte
     * aucun siège ou contient un caractère inconnu.
     */
    fun parse(encoded: Any?): SeatVotes? {
      val text = encoded as? String ?: return null
      if (text.isEmpty() || text.length > MAX_PLACES) return null
      val byPlace = mutableMapOf<Int, SeatVote>()
      text.forEachIndexed { i, char ->
        if (char != EMPTY_PLACE) byPlace[i + 1] = SeatVote.of(char) ?: return null
      }
      return SeatVotes(byPlace).takeIf { byPlace.isNotEmpty() }
    }

    /**
     * Lit les sièges du fichier de détail (`seats`, un tableau `[place, groupe, vote]` par siège),
     * mêmes règles que `HemicycleSeat.tryParseList` : `null` s'ils sont absents ou vides, ou si un
     * seul siège est illisible (vote inconnu, place manquante, nulle ou en double, groupe vide).
     */
    fun fromDetailSeats(json: JSONArray?): SeatVotes? {
      if (json == null || json.length() == 0) return null
      val byPlace = mutableMapOf<Int, SeatVote>()
      for (i in 0 until json.length()) {
        val seat = json.opt(i) as? JSONArray ?: return null
        if (seat.length() != 3) return null
        val place =
            when (val value = seat.opt(0)) {
              is Int -> value.toLong()
              is Long -> value
              else -> return null
            }
        if (place <= 0 || place > MAX_PLACES || byPlace.containsKey(place.toInt())) return null
        if ((seat.opt(1) as? String).isNullOrEmpty()) return null
        val letter = (seat.opt(2) as? String)?.singleOrNull() ?: return null
        byPlace[place.toInt()] = SeatVote.of(letter) ?: return null
      }
      return SeatVotes(byPlace)
    }

    /**
     * Sièges d'un fichier de détail publié (`v1/decisions/<id>.json`) ; `null` s'il est illisible,
     * d'une autre version, d'une autre décision que [id] ou sans sièges.
     */
    fun fromDetail(json: String, id: String): SeatVotes? {
      val root =
          try {
            JSONObject(json)
          } catch (e: Exception) {
            return null
          }
      if (root.opt("schemaVersion") != 1) return null
      if (root.optJSONObject("decision")?.opt("id") != id) return null
      return fromDetailSeats(root.optJSONArray("seats"))
    }
  }
}

/** Apparence d'un siège : la couleur du vote ; l'abstention en plus petit, absents estompés. */
enum class SeatKind(val radiusScale: Float) {
  POUR(1f),
  CONTRE(1f),
  ABSTENTION(0.5f),
  OFF(1f);

  companion object {
    fun of(vote: SeatVote): SeatKind =
        when (vote) {
          SeatVote.POUR -> POUR
          SeatVote.CONTRE -> CONTRE
          SeatVote.ABSTENTION -> ABSTENTION
          SeatVote.NON_VOTANT,
          SeatVote.ABSENT -> OFF
        }
  }
}

/**
 * Sièges à dessiner, groupés par apparence, dans le repère de [HemicycleGeometry] : `x, y` à la
 * suite. Une place inconnue du plan n'est pas dessinée.
 */
data class HemicycleLayout(val dots: Map<SeatKind, FloatArray>) {
  /** Nombre de sièges dessinés. */
  val count: Int
    get() = dots.values.sumOf { it.size / 2 }

  companion object {
    fun of(votes: SeatVotes): HemicycleLayout {
      val points = mutableMapOf<SeatKind, MutableList<Float>>()
      HemicycleGeometry.PLACES.forEachIndexed { i, place ->
        val vote = votes.byPlace[place] ?: return@forEachIndexed
        points
            .getOrPut(SeatKind.of(vote)) { mutableListOf() }
            .apply {
              add(HemicycleGeometry.XS[i])
              add(HemicycleGeometry.YS[i])
            }
      }
      // Dans l'ordre des apparences : estompés dessous.
      return HemicycleLayout(
          SeatKind.entries
              .sortedBy { if (it == SeatKind.OFF) -1 else it.ordinal }
              .mapNotNull { kind -> points[kind]?.let { kind to it.toFloatArray() } }
              .toMap())
    }
  }
}
