package com.lucasangoston.votedujour.widget

import java.time.Instant
import java.time.LocalDate
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Prochain vote solennel des widgets (#56) : conversion, lecture et règle d'affichage. */
class UpcomingVoteTest {
  private val savedAt = Instant.parse("2026-10-21T08:00:00Z")

  private fun upcoming(
      id: String,
      kind: String = "vote_solennel",
      startsAt: String,
      shortTitle: String = "budget",
  ) =
      """{"id":"$id","kind":"$kind","startsAt":"$startsAt","seanceRef":"RUANS1",
      "label":"Vote solennel","shortTitle":"$shortTitle"}"""

  private fun convert(upcoming: List<String>?): JSONObject {
    val block = upcoming?.let { ""","upcoming":[${it.joinToString(",")}]""" }.orEmpty()
    val index =
        """{"schemaVersion":1,"decisions":[{"id":"VTANR5L17V8730","numero":8730,
        "type":"ensemble","status":"confirmee","result":"adopte","date":"2026-10-15",
        "officialTitle":"t","sourceUrl":"https://example.test/s"}]$block}"""
    return JSONObject(SnapshotConverter.fromIndex(index, savedAt)!!)
  }

  @Test
  fun garde_les_votes_solennels_du_plus_proche_au_plus_lointain() {
    val snapshot =
        convert(
            listOf(
                upcoming("PT3", startsAt = "2026-11-03T14:00:00Z", shortTitle = "budget 2027"),
                upcoming("PT1", kind = "discussion", startsAt = "2026-10-22T13:00:00Z"),
                upcoming(
                    "PT2",
                    startsAt = "2026-10-27T14:00:00.000Z",
                    shortTitle = " Budget de la Sécurité sociale pour 2027 ",
                ),
                // Malformés : nature inconnue, date illisible, titre vide, séance absente.
                upcoming("PT4", kind = "question", startsAt = "2026-10-28T14:00:00Z"),
                upcoming("PT5", startsAt = "mardi"),
                upcoming("PT6", startsAt = "2026-10-28T14:00:00Z", shortTitle = " "),
                upcoming("PT7", startsAt = "2026-10-28T14:00:00Z")
                    .replace("\"seanceRef\":\"RUANS1\",", ""),
            )
        )

    val votes = snapshot.getJSONArray("upcomingVotes")
    assertEquals(2, votes.length())
    votes.getJSONObject(0).let {
      assertEquals("PT2", it.getString("id"))
      assertEquals("2026-10-27T14:00:00Z", it.getString("startsAt"))
      assertEquals("Budget de la Sécurité sociale pour 2027", it.getString("title"))
    }
    assertEquals("Budget 2027", votes.getJSONObject(1).getString("title"))
    // Le widget relit l'instantané produit.
    val read = DecisionSnapshot.parse(snapshot.toString())!!
    assertEquals(listOf("PT2", "PT3"), read.upcomingVotes.map { it.id })
    assertEquals(1, read.decisions.size)
  }

  @Test
  fun sans_vote_solennel_le_champ_est_omis() {
    listOf(
            null,
            emptyList(),
            listOf(upcoming("PT1", kind = "discussion", startsAt = "2026-10-22T13:00:00Z")),
        )
        .forEach { assertEquals(false, convert(it).has("upcomingVotes")) }
  }

  @Test
  fun lit_un_ancien_instantane_et_ignore_les_votes_illisibles() {
    val old = """{"version":1,"savedAt":"2026-10-17T00:00:00.000Z","decisions":[]}"""
    assertEquals(emptyList<UpcomingVote>(), DecisionSnapshot.parse(old)!!.upcomingVotes)
    val mixed =
        """{"version":1,"savedAt":"2026-10-17T00:00:00.000Z","decisions":[],"upcomingVotes":[
        {"id":"a","startsAt":"demain","title":"t"},
        {"id":"b","startsAt":"2026-10-27T14:00:00Z","title":" "},
        {"id":"c","startsAt":"2026-10-27T15:00:00+01:00","title":"t"},"d"]}"""
    val read = DecisionSnapshot.parse(mixed)!!.upcomingVotes
    assertEquals(listOf("c"), read.map { it.id })
    assertEquals(Instant.parse("2026-10-27T14:00:00Z"), read.single().startsAt)
    val invalid = """{"version":1,"savedAt":"x","decisions":[],"upcomingVotes":"aucun"}"""
    assertEquals(emptyList<UpcomingVote>(), DecisionSnapshot.parse(invalid)!!.upcomingVotes)
  }

  @Test
  fun libelle_du_jour_a_paris() {
    val plfss = UpcomingVote("a", Instant.parse("2026-10-27T14:00:00Z"), "t")
    assertEquals("mar. 27 oct.", plfss.dayLabel)
    assertEquals("Vote · mar. 15 h", plfss.whenLabel)
    assertEquals("Prochain vote solennel, mar. 27 oct. à 15 h. t", plfss.accessibilityLabel)
    // 23 h 30 UTC le 30 novembre : déjà le 1er décembre à Paris.
    val late = UpcomingVote("b", Instant.parse("2026-11-30T23:30:00Z"), "t")
    assertEquals("mar. 1er déc.", late.dayLabel)
  }

  @Test
  fun annonce_seulement_sans_decision_recente() {
    val votes =
        listOf(
            UpcomingVote("passe", Instant.parse("2026-10-20T13:00:00Z"), "t"),
            UpcomingVote("plfss", Instant.parse("2026-10-27T14:00:00Z"), "t"),
        )
    fun shown(latest: LocalDate?, today: LocalDate) = UpcomingVote.shown(votes, latest, today)?.id

    val oct17 = LocalDate.of(2026, 10, 17)
    // Dernière décision le 17 : trois jours le 20, quatre le 21.
    assertNull(shown(oct17, LocalDate.of(2026, 10, 20)))
    assertEquals("plfss", shown(oct17, LocalDate.of(2026, 10, 21)))
    assertEquals("plfss", shown(null, LocalDate.of(2026, 10, 21)))
    // Le jour du vote, il est encore annoncé ; le lendemain, plus rien.
    assertEquals("passe", shown(LocalDate.of(2026, 10, 13), LocalDate.of(2026, 10, 20)))
    assertEquals("plfss", shown(oct17, LocalDate.of(2026, 10, 27)))
    assertNull(shown(oct17, LocalDate.of(2026, 10, 28)))
    assertNull(UpcomingVote.shown(emptyList(), null))
  }
}
