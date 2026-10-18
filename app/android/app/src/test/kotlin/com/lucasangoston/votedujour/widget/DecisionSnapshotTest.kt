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
  fun lit_le_decompte_et_le_mode_de_vote_optionnels() {
    val json =
        """{"version":1,"savedAt":"2026-10-17T10:17:00.000Z","decisions":[
        {"id":"a","result":"adopte","date":"2026-10-13","title":"A",
         "count":{"pour":503,"contre":0,"abstentions":67},"voteMode":"scrutin_public"},
        {"id":"b","result":"adopte","date":"2026-10-12","title":"B","voteMode":"main_levee"},
        {"id":"c","result":"rejete","date":"2026-10-11","title":"C"},
        {"id":"d","result":"rejete","date":"2026-10-10","title":"D",
         "count":{"pour":"x","contre":1,"abstentions":1},"voteMode":"inconnu"},
        {"id":"e","result":"rejete","date":"2026-10-10","title":"E","count":{"pour":1.5,"contre":1,"abstentions":1}}]}"""

    val decisions = DecisionSnapshot.parse(json)!!.decisions

    assertEquals(5, decisions.size)
    assertEquals(VoteCount(503, 0, 67), decisions[0].count)
    assertEquals(VoteMode.SCRUTIN_PUBLIC, decisions[0].voteMode)
    assertEquals(VoteMode.MAIN_LEVEE, decisions[1].voteMode)
    assertEquals(null, decisions[1].count)
    // Instantané ancien : ni décompte ni mode.
    assertEquals(null, decisions[2].count)
    assertEquals(null, decisions[2].voteMode)
    // Valeurs illisibles : ignorées, la décision reste.
    assertEquals(null, decisions[3].count)
    assertEquals(null, decisions[3].voteMode)
    assertEquals(null, decisions[4].count)
  }

  @Test
  fun nombre_nul_ou_negatif() {
    assertEquals(emptyList<String>(), snapshot("a").latest(0).map { it.id })
    assertEquals(emptyList<String>(), snapshot("a").latest(-1).map { it.id })
  }
}
