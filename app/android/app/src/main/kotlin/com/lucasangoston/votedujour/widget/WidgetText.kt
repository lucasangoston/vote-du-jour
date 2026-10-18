package com.lucasangoston.votedujour.widget

import java.time.LocalDate

/** Textes des widgets (charte Hémicycle, #29), séparés du rendu Glance pour être testés. */
object WidgetText {
  private const val SEPARATOR = " · "

  fun result(result: VoteResult): String =
      when (result) {
        VoteResult.ADOPTE -> "Adopté"
        VoteResult.REJETE -> "Rejeté"
      }

  /** Petit widget : « Il y a 5 jours », suivi des mentions (« · provisoire »). */
  fun smallDate(decision: WidgetDecision, today: LocalDate = LocalDate.now()): String =
      (listOf(RelativeDate.label(decision.date, today)) + decision.mentions).joinToString(SEPARATOR)

  /** Widget moyen : « 1re lecture à l'AN · il y a 5 jours » (l'étape porte déjà les mentions). */
  fun mediumMeta(decision: WidgetDecision, today: LocalDate = LocalDate.now()): String =
      decision.stage?.let { "$it$SEPARATOR${RelativeDate.inline(decision.date, today)}" }
          ?: RelativeDate.label(decision.date, today)

  /** Grand widget, après le résultat : « · à main levée · il y a 11 jours ». */
  fun largeMeta(decision: WidgetDecision, today: LocalDate = LocalDate.now()): String =
      (decision.mentions + RelativeDate.inline(decision.date, today)).joinToString(
          separator = SEPARATOR,
          prefix = SEPARATOR,
      )

  /** Lecture d'écran de l'arc : « 503 pour, 0 contre, 67 abstentions », ou le mode de vote. */
  fun arcDescription(decision: WidgetDecision): String? =
      when {
        decision.isMainLevee -> "Vote à main levée"
        else -> decision.count?.description
      }

  /** Lecture d'écran d'une ligne ou d'un widget entier. */
  fun description(decision: WidgetDecision, today: LocalDate = LocalDate.now()): String =
      listOfNotNull(
              result(decision.result),
              arcDescription(decision),
              decision.title,
              decision.stage,
              RelativeDate.label(decision.date, today),
          )
          .joinToString(". ")
}
