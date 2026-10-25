package com.lucasangoston.votedujour.widget

/** Textes des widgets (charte Hémicycle, #29), séparés du rendu Glance pour être testés. */
object WidgetText {
  fun result(result: VoteResult): String =
      when (result) {
        VoteResult.ADOPTE -> "Adopté"
        VoteResult.REJETE -> "Rejeté"
      }
}
