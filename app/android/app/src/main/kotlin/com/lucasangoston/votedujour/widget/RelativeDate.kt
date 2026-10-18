package com.lucasangoston.votedujour.widget

import java.time.LocalDate
import java.time.temporal.ChronoUnit

/**
 * Dates relatives des décisions (« Aujourd'hui », « Hier », « Il y a 3 jours »), calculées au
 * moment du rendu. Mêmes règles que l'app (`lib/src/relative_date.dart`) :
 * - l'écart se compte en jours de calendrier dans le fuseau du téléphone (un vote du vendredi est
 *   « Il y a 3 jours » le lundi) ;
 * - au-delà de six jours, la date complète (« 13 octobre 2026 ») ;
 * - une date future (horloge décalée) est affichée comme « Aujourd'hui ».
 */
object RelativeDate {
  private val MONTHS =
      listOf(
          "janvier",
          "février",
          "mars",
          "avril",
          "mai",
          "juin",
          "juillet",
          "août",
          "septembre",
          "octobre",
          "novembre",
          "décembre",
      )

  fun label(day: LocalDate, today: LocalDate = LocalDate.now()): String {
    val days = ChronoUnit.DAYS.between(day, today)
    return when {
      days <= 0 -> "Aujourd'hui"
      days == 1L -> "Hier"
      days < 7 -> "Il y a $days jours"
      else -> fullDate(day)
    }
  }

  /** [label] en milieu de ligne, après « · » : « il y a 3 jours », « hier ». */
  fun inline(day: LocalDate, today: LocalDate = LocalDate.now()): String =
      label(day, today).replaceFirstChar { it.lowercase() }

  /** « 13 octobre 2026 » (« 1er » pour le premier du mois). */
  fun fullDate(day: LocalDate): String {
    val dayOfMonth = if (day.dayOfMonth == 1) "1er" else day.dayOfMonth.toString()
    return "$dayOfMonth ${MONTHS[day.monthValue - 1]} ${day.year}"
  }
}
