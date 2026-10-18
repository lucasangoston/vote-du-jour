package com.lucasangoston.votedujour.widget

import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Test

/** Textes des widgets et mentions tirées de l'étape. */
class WidgetTextTest {
  private val today = LocalDate.of(2026, 10, 18)

  private fun decision(stage: String? = null, voteMode: VoteMode? = null, count: VoteCount? = null) =
      WidgetDecision(
          id = "a",
          result = VoteResult.ADOPTE,
          date = LocalDate.of(2026, 10, 13),
          title = "Titre",
          stage = stage,
          voteMode = voteMode,
          count = count,
      )

  @Test
  fun mentions_de_l_etape() {
    assertEquals(
        listOf("à main levée", "provisoire"),
        decision("1re lecture à l'AN · à main levée · provisoire").mentions,
    )
    assertEquals(listOf("provisoire"), decision("Provisoire").mentions)
    assertEquals(emptyList<String>(), decision("1re lecture à l'AN").mentions)
    assertEquals(emptyList<String>(), decision(null).mentions)
  }

  @Test
  fun main_levee_d_apres_le_mode_ou_a_defaut_l_etape() {
    assertEquals(true, decision(voteMode = VoteMode.MAIN_LEVEE).isMainLevee)
    assertEquals(false, decision("À main levée", VoteMode.SCRUTIN_PUBLIC).isMainLevee)
    // Instantané écrit avant `voteMode` : la mention suffit.
    assertEquals(true, decision("À main levée").isMainLevee)
    assertEquals(false, decision("1re lecture à l'AN").isMainLevee)
  }

  @Test
  fun petit_widget_date_et_mentions() {
    assertEquals("Il y a 5 jours", WidgetText.smallDate(decision("1re lecture à l'AN"), today))
    assertEquals(
        "Il y a 5 jours · provisoire",
        WidgetText.smallDate(decision("1re lecture à l'AN · provisoire"), today),
    )
  }

  @Test
  fun widget_moyen_etape_puis_date() {
    assertEquals(
        "1re lecture à l'AN · il y a 5 jours",
        WidgetText.mediumMeta(decision("1re lecture à l'AN"), today),
    )
    assertEquals("Il y a 5 jours", WidgetText.mediumMeta(decision(), today))
  }

  @Test
  fun grand_widget_apres_le_resultat() {
    assertEquals(" · à main levée · il y a 5 jours", WidgetText.largeMeta(decision("À main levée"), today))
    assertEquals(" · hier", WidgetText.largeMeta(decision().copy(date = today.minusDays(1)), today))
    assertEquals(" · 1er octobre 2026", WidgetText.largeMeta(decision().copy(date = LocalDate.of(2026, 10, 1)), today))
  }

  @Test
  fun lecture_d_ecran() {
    assertEquals(
        "Adopté. 503 pour, 0 contre, 67 abstentions. Titre. Il y a 5 jours",
        WidgetText.description(decision(count = VoteCount(503, 0, 67)), today),
    )
    assertEquals(
        "Adopté. Vote à main levée. Titre. À main levée. Il y a 5 jours",
        WidgetText.description(decision("À main levée", VoteMode.MAIN_LEVEE), today),
    )
  }

  @Test
  fun pas_de_tiret_cadratin() {
    val texts =
        listOf(
            WidgetText.smallDate(decision("x · provisoire"), today),
            WidgetText.mediumMeta(decision("x"), today),
            WidgetText.largeMeta(decision("à main levée"), today),
            WidgetText.description(decision("x", count = VoteCount(1, 2, 3)), today),
        )
    texts.forEach { assertEquals(false, it.contains('—')) }
  }
}
