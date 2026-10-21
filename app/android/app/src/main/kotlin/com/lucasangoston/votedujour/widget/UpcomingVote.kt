package com.lucasangoston.votedujour.widget

import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import org.json.JSONObject

/**
 * Vote solennel inscrit à l'ordre du jour (#56), tel que l'instantané le donne : `{"id": "…",
 * "startsAt": "2026-10-27T14:00:00.000Z", "title": "…"}`. Les widgets l'annoncent quand la dernière
 * décision a plus de trois jours.
 */
data class UpcomingVote(
    val id: String,
    /** Début de la séance. */
    val startsAt: Instant,
    /** Titre court, prêt à afficher. */
    val title: String,
) {
  /** Jour de la séance, à Paris. */
  val day: LocalDate
    get() = startsAt.atZone(PARIS).toLocalDate()

  /** « mar. 27 oct. » (« 1er » pour le premier du mois). */
  val dayLabel: String
    get() = "$weekdayLabel $dayOfMonthLabel $monthLabel"

  /** « mar. » */
  val weekdayLabel: String
    get() = WEEKDAYS[day.dayOfWeek.value - 1]

  /** « 27 » (« 1er »). */
  val dayOfMonthLabel: String
    get() = if (day.dayOfMonth == 1) "1er" else day.dayOfMonth.toString()

  /** « oct. » */
  val monthLabel: String
    get() = MONTHS[day.monthValue - 1]

  fun toJson(): JSONObject =
      JSONObject().put("id", id).put("startsAt", startsAt.toString()).put("title", title)

  companion object {
    /** Au-delà de ce nombre de jours sans décision, les widgets annoncent le prochain vote. */
    const val STALE_AFTER_DAYS = 3L

    private val PARIS: ZoneId = ZoneId.of("Europe/Paris")
    private val WEEKDAYS = listOf("lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim.")
    private val MONTHS =
        listOf(
            "janv.",
            "févr.",
            "mars",
            "avr.",
            "mai",
            "juin",
            "juil.",
            "août",
            "sept.",
            "oct.",
            "nov.",
            "déc.",
        )

    /**
     * Vote à annoncer [today] : le premier de [votes] dont le jour (à Paris) n'est pas passé, si la
     * dernière décision ([latestDecisionDay]) a plus de [STALE_AFTER_DAYS] jours ou s'il n'y en a
     * pas. Jours de calendrier, comme les dates relatives.
     */
    fun shown(
        votes: List<UpcomingVote>,
        latestDecisionDay: LocalDate?,
        today: LocalDate = LocalDate.now(),
    ): UpcomingVote? {
      val age = latestDecisionDay?.let { ChronoUnit.DAYS.between(it, today) }
      if (age != null && age <= STALE_AFTER_DAYS) return null
      return votes.firstOrNull { !it.day.isBefore(today) }
    }

    /** Instant ISO 8601 avec fuseau (`Z` ou décalage) ; `null` s'il est illisible. */
    fun instant(value: String?): Instant? =
        try {
          value?.let { OffsetDateTime.parse(it).toInstant() }
        } catch (e: Exception) {
          null
        }

    /** Un vote illisible (date, titre vide) est ignoré. */
    fun parse(json: JSONObject): UpcomingVote? {
      val id = json.opt("id") as? String ?: return null
      val startsAt = instant(json.opt("startsAt") as? String) ?: return null
      val title = (json.opt("title") as? String)?.takeIf { it.isNotBlank() } ?: return null
      return UpcomingVote(id, startsAt, title)
    }
  }
}
