package com.lucasangoston.votedujour.widget

import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Test

/** Textes des widgets et mentions tirées de l'étape. */
class WidgetTextTest {
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
  fun lecture_d_ecran() {
    assertEquals(
        "Adopté. Titre. 503 pour, 0 contre, 67 abstentions.",
        decision(count = VoteCount(503, 0, 67)).accessibilityLabel,
    )
    assertEquals(
        "Adopté. Titre. Vote à main levée. Décision provisoire.",
        decision("À main levée · provisoire", VoteMode.MAIN_LEVEE).accessibilityLabel,
    )
    assertEquals("Adopté. Fin.", decision().copy(title = "Fin.").accessibilityLabel)
  }

  @Test
  fun date_courte_du_widget_moyen() {
    assertEquals("13 oct.", decision().shortDateLabel)
    assertEquals("1er nov.", decision().copy(date = LocalDate.of(2026, 11, 1)).shortDateLabel)
  }

  @Test
  fun pas_de_tiret_cadratin() {
    val texts =
        listOf(
            decision("x · provisoire", count = VoteCount(1, 2, 3)).accessibilityLabel,
            decision().shortDateLabel,
        )
    texts.forEach { assertEquals(false, it.contains('—')) }
  }
}
