package com.lucasangoston.votedujour.widget

import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import org.json.JSONObject

/**
 * Instantané écrit par l'app (`lib/src/home_widget/widget_snapshot.dart`) dans les préférences de
 * home_widget. Les champs optionnels absents ne sont pas affichés.
 */
data class DecisionSnapshot(val decisions: List<WidgetDecision>) {
  /**
   * Les [count] décisions les plus récentes, de la plus récente à la plus ancienne (l'instantané
   * est déjà dans cet ordre). Moins s'il en contient moins ; aucune pour un [count] négatif ou nul.
   */
  fun latest(count: Int): List<WidgetDecision> = decisions.take(count.coerceAtLeast(0))

  companion object {
    const val STORAGE_KEY = "decisions_snapshot"
    private const val SUPPORTED_VERSION = 1

    /** `null` si l'app n'a pas encore écrit l'instantané ou s'il est d'une version inconnue. */
    fun parse(json: String?): DecisionSnapshot? {
      if (json.isNullOrBlank()) return null
      return try {
        val root = JSONObject(json)
        if (root.optInt("version") != SUPPORTED_VERSION) return null
        val items = root.getJSONArray("decisions")
        DecisionSnapshot(
            (0 until items.length()).mapNotNull { i ->
              items.optJSONObject(i)?.let(WidgetDecision::parse)
            }
        )
      } catch (e: Exception) {
        null
      }
    }
  }
}

enum class VoteResult {
  ADOPTE,
  REJETE,
}

data class WidgetDecision(
    val id: String,
    val result: VoteResult,
    /** Jour du vote. */
    val date: LocalDate,
    val title: String,
    val stage: String? = null,
    val explanation: String? = null,
) {
  /** « 13 octobre 2026 » (« 1er » pour le premier du mois). */
  val dateLabel: String
    get() {
      val day = if (date.dayOfMonth == 1) "1er" else date.dayOfMonth.toString()
      return "$day ${date.format(MONTH_YEAR)}"
    }

  companion object {
    private val MONTH_YEAR = DateTimeFormatter.ofPattern("MMMM yyyy", Locale.FRENCH)

    /** Une décision illisible (valeur inconnue ajoutée par une version plus récente) est ignorée. */
    fun parse(json: JSONObject): WidgetDecision? =
        try {
          WidgetDecision(
              id = json.getString("id"),
              result =
                  when (json.getString("result")) {
                    "adopte" -> VoteResult.ADOPTE
                    "rejete" -> VoteResult.REJETE
                    else -> return null
                  },
              date = LocalDate.parse(json.getString("date")),
              title = json.getString("title"),
              stage = json.optStringOrNull("stage"),
              explanation = json.optStringOrNull("explanation"),
          )
        } catch (e: Exception) {
          null
        }

    private fun JSONObject.optStringOrNull(key: String): String? =
        if (has(key) && !isNull(key)) getString(key) else null

    val SAMPLE =
        WidgetDecision(
            id = "exemple",
            result = VoteResult.ADOPTE,
            date = LocalDate.of(2026, 10, 13),
            title = "L'ensemble du projet de loi relatif à la simplification de la vie économique.",
        )
  }
}
