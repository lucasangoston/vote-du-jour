package com.lucasangoston.votedujour.widget

import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Test

/** Sélection des décisions affichées par les widgets ([DecisionSnapshot.latest]). */
class DecisionSnapshotTest {
  private fun snapshot(vararg ids: String) =
      DecisionSnapshot(
          ids.map {
            WidgetDecision(
                id = it,
                result = VoteResult.ADOPTE,
                date = LocalDate.of(2026, 10, 13),
                title = "Titre $it",
            )
          })

  @Test
  fun grand_widget_les_trois_plus_recentes_dans_l_ordre() {
    val latest = snapshot("a", "b", "c", "d", "e").latest(LargeDecisionWidget.LARGE_WIDGET_COUNT)
    assertEquals(listOf("a", "b", "c"), latest.map { it.id })
  }

  @Test
  fun moins_de_decisions_que_demande() {
    assertEquals(listOf("a", "b"), snapshot("a", "b").latest(3).map { it.id })
    assertEquals(emptyList<String>(), snapshot().latest(3).map { it.id })
  }

  @Test
  fun petit_et_moyen_la_derniere() {
    assertEquals(listOf("a"), snapshot("a", "b", "c").latest(1).map { it.id })
  }

  @Test
  fun nombre_nul_ou_negatif() {
    assertEquals(emptyList<String>(), snapshot("a").latest(0).map { it.id })
    assertEquals(emptyList<String>(), snapshot("a").latest(-1).map { it.id })
  }
}
