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

/** Mode de vote : scrutin public (avec décompte) ou main levée (sans décompte). */
enum class VoteMode(val json: String) {
  SCRUTIN_PUBLIC("scrutin_public"),
  MAIN_LEVEE("main_levee");

  companion object {
    /** `null` pour une valeur absente ou inconnue. */
    fun parse(value: Any?): VoteMode? = entries.firstOrNull { it.json == value }
  }
}

/** Décompte d'un scrutin public : pour, contre et abstentions. */
data class VoteCount(val pour: Int, val contre: Int, val abstentions: Int) {
  /** Base de l'arc du vote : pour + contre + abstentions. */
  val total: Long
    get() = pour.toLong() + contre + abstentions

  /** « 503 · 0 · 67 » (pour · contre · abstentions). */
  val label: String
    get() = "$pour · $contre · $abstentions"

  /** Lecture d'écran : « 503 pour, 0 contre, 67 abstentions ». */
  val description: String
    get() = "$pour pour, $contre contre, $abstentions abstentions"

  fun toJson(): JSONObject =
      JSONObject().put("pour", pour).put("contre", contre).put("abstentions", abstentions)

  companion object {
    /**
     * `{"pour":503,"contre":0,"abstentions":67}` ; `null` si un nombre manque, n'est pas entier ou
     * est négatif. Les autres clés (`nonVotants`) sont ignorées.
     */
    fun parse(json: JSONObject?): VoteCount? {
      if (json == null) return null
      return VoteCount(
          pour = json.count("pour") ?: return null,
          contre = json.count("contre") ?: return null,
          abstentions = json.count("abstentions") ?: return null,
      )
    }

    private fun JSONObject.count(key: String): Int? {
      val value = opt(key)
      val long =
          when (value) {
            is Int -> value.toLong()
            is Long -> value
            else -> return null
          }
      return long.takeIf { it in 0..Int.MAX_VALUE }?.toInt()
    }
  }
}

data class WidgetDecision(
    val id: String,
    val result: VoteResult,
    /** Jour du vote. */
    val date: LocalDate,
    val title: String,
    val stage: String? = null,
    val explanation: String? = null,
    /** Décompte du scrutin ; absent à main levée ou dans un instantané plus ancien. */
    val count: VoteCount? = null,
    /** Mode de vote ; absent dans un instantané plus ancien. */
    val voteMode: VoteMode? = null,
) {
  /** « 13 octobre 2026 » (« 1er » pour le premier du mois). */
  val dateLabel: String
    get() {
      val day = if (date.dayOfMonth == 1) "1er" else date.dayOfMonth.toString()
      return "$day ${date.format(MONTH_YEAR)}"
    }

  /**
   * Mentions « à main levée » et « provisoire » que l'app et le fetcher ajoutent à l'étape, en
   * minuscules et dans leur ordre. Les widgets qui n'affichent pas l'étape les montrent quand même.
   */
  val mentions: List<String>
    get() = stage.orEmpty().split(" · ").map { it.trim().lowercase() }.filter { it in MENTIONS }

  /**
   * Vote à main levée : d'après [voteMode], ou à défaut d'après la mention de l'étape (instantanés
   * écrits avant l'ajout de `voteMode`).
   */
  val isMainLevee: Boolean
    get() = voteMode?.let { it == VoteMode.MAIN_LEVEE } ?: (MAIN_LEVEE_MENTION in mentions)

  /** Arc du vote dessiné par les widgets. */
  val arc: VoteArc
    get() = VoteArc.of(result, count, isMainLevee)

  companion object {
    private val MONTH_YEAR = DateTimeFormatter.ofPattern("MMMM yyyy", Locale.FRENCH)

    const val MAIN_LEVEE_MENTION = "à main levée"
    const val PROVISIONAL_MENTION = "provisoire"
    private val MENTIONS = setOf(MAIN_LEVEE_MENTION, PROVISIONAL_MENTION)

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
              // Champs optionnels : un décompte ou un mode illisible n'écarte pas la décision.
              count = VoteCount.parse(json.optJSONObject("count")),
              voteMode = VoteMode.parse(json.opt("voteMode")),
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
            count = VoteCount(pour = 503, contre = 0, abstentions = 67),
            voteMode = VoteMode.SCRUTIN_PUBLIC,
        )
  }
}
