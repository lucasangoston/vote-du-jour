package com.lucasangoston.votedujour.widget

import java.time.Instant
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SnapshotConverterTest {
  private val savedAt = Instant.parse("2026-10-17T11:30:00Z")

  private fun decision(numero: Int, extra: String = "") =
      """{"id":"VTANR5L17V$numero","numero":$numero,"type":"ensemble","status":"confirmee",
      "result":"adopte","date":"2026-10-1${numero % 10}",
      "officialTitle":"l'ensemble du projet de loi n° $numero.",
      "sourceUrl":"https://www.assemblee-nationale.fr/dyn/17/scrutins/$numero"$extra}"""

  @Test
  fun garde_les_trois_premieres_decisions_lisibles() {
    val index =
        """{"schemaVersion":1,"generatedAt":"2026-10-17T10:00:00.000Z","decisions":[
        ${decision(8715, ""","shortTitle":"budget 2027","stage":"1re lecture à l'AN"""")},
        ${decision(8714).replace("\"ensemble\"", "\"inconnu\"")},
        ${decision(8713, ",\"shortTitle\":\"  \",\"stage\":\"\"")},
        ${decision(8712)},
        ${decision(8711)}]}"""

    val snapshot = JSONObject(SnapshotConverter.fromIndex(index, savedAt)!!)

    assertEquals(1, snapshot.getInt("version"))
    assertEquals("2026-10-17T11:30:00Z", snapshot.getString("savedAt"))
    val decisions = snapshot.getJSONArray("decisions")
    assertEquals(3, decisions.length())
    decisions.getJSONObject(0).let {
      assertEquals("VTANR5L17V8715", it.getString("id"))
      assertEquals("adopte", it.getString("result"))
      assertEquals("2026-10-15", it.getString("date"))
      assertEquals("Budget 2027", it.getString("title"))
      assertEquals("1re lecture à l'AN", it.getString("stage"))
    }
    decisions.getJSONObject(1).let {
      assertEquals("VTANR5L17V8713", it.getString("id"))
      assertEquals("L'ensemble du projet de loi n° 8713.", it.getString("title"))
      assertEquals(false, it.has("stage"))
    }
    assertEquals("VTANR5L17V8712", decisions.getJSONObject(2).getString("id"))
  }

  @Test
  fun accepte_les_votes_a_main_levee_sans_numero() {
    val mainLevee =
        """{"id":"L17-VD234087DEC","voteMode":"main_levee","type":"ensemble",
        "status":"confirmee","result":"adopte","date":"2026-10-07",
        "officialTitle":"projet de loi GloBE","sourceUrl":"https://example.test/d""""
    val index =
        """{"schemaVersion":1,"decisions":[
        $mainLevee,"stage":"1re lecture à l'AN"},
        $mainLevee},
        ${decision(8717).replace("\"numero\":8717,", "")},
        ${decision(8718).replace("\"ensemble\",", "\"ensemble\",\"voteMode\":\"inconnu\",")},
        ${decision(8719).replace("\"numero\":8719,", "\"voteMode\":\"scrutin_public\",\"numero\":8719,")}]}"""

    val decisions = JSONObject(SnapshotConverter.fromIndex(index, savedAt)!!).getJSONArray("decisions")

    assertEquals(3, decisions.length())
    assertEquals("1re lecture à l'AN · à main levée", decisions.getJSONObject(0).getString("stage"))
    assertEquals("Projet de loi GloBE", decisions.getJSONObject(0).getString("title"))
    assertEquals("À main levée", decisions.getJSONObject(1).getString("stage"))
    // Scrutin public sans numéro et mode inconnu : ignorés.
    assertEquals("VTANR5L17V8719", decisions.getJSONObject(2).getString("id"))
  }

  @Test
  fun ajoute_provisoire_a_l_etape() {
    val index =
        """{"schemaVersion":1,"decisions":[
        ${decision(8721, ""","stage":"1re lecture à l'AN"""").replace("\"confirmee\"", "\"provisoire\"")},
        ${decision(8720).replace("\"confirmee\"", "\"provisoire\"")},
        ${decision(8719, ""","stage":"1re lecture à l'AN"""").replace("\"status\":\"confirmee\",", "")},
        ${decision(8718).replace("\"confirmee\"", "\"annulee\"")}]}"""

    val decisions = JSONObject(SnapshotConverter.fromIndex(index, savedAt)!!).getJSONArray("decisions")

    assertEquals(3, decisions.length())
    assertEquals("1re lecture à l'AN · provisoire", decisions.getJSONObject(0).getString("stage"))
    assertEquals("L'ensemble du projet de loi n° 8721.", decisions.getJSONObject(0).getString("title"))
    assertEquals("Provisoire", decisions.getJSONObject(1).getString("stage"))
    // `status` absent : confirmée ; statut inconnu : ignorée.
    assertEquals("1re lecture à l'AN", decisions.getJSONObject(2).getString("stage"))
  }

  @Test
  fun lit_le_titre_et_la_phrase_du_resume() {
    val summary =
        ""","summary":{"title":"retraite à 62 ans","explanation":" Le texte prévoit… ","promptVersion":1}"""
    val malformed = ""","shortTitle":"budget","summary":{"title":"x","explanation":"y"}"""
    val index =
        """{"schemaVersion":1,"decisions":[
        ${decision(8724, ""","shortTitle":"budget"""" + summary)},
        ${decision(8723, malformed)},
        ${decision(8722)}]}"""

    val decisions = JSONObject(SnapshotConverter.fromIndex(index, savedAt)!!).getJSONArray("decisions")

    assertEquals(3, decisions.length())
    assertEquals("Retraite à 62 ans", decisions.getJSONObject(0).getString("title"))
    assertEquals("Le texte prévoit…", decisions.getJSONObject(0).getString("explanation"))
    // Résumé malformé (pas de version) : ignoré, la décision reste lisible.
    assertEquals("Budget", decisions.getJSONObject(1).getString("title"))
    assertEquals(false, decisions.getJSONObject(1).has("explanation"))
    assertEquals(false, decisions.getJSONObject(2).has("explanation"))
  }

  @Test
  fun recopie_le_decompte_et_le_mode_de_vote() {
    val count = ""","count":{"pour":503,"contre":0,"abstentions":67,"nonVotants":4}"""
    val mainLevee =
        """{"id":"L17-VD234087DEC","voteMode":"main_levee","type":"ensemble",
        "status":"confirmee","result":"adopte","date":"2026-10-07",
        "officialTitle":"projet de loi GloBE","sourceUrl":"https://example.test/d"}"""
    val index =
        """{"schemaVersion":1,"decisions":[
        ${decision(8730, count)},
        $mainLevee,
        ${decision(8729, ""","count":{"pour":1,"contre":-2,"abstentions":0}""")}]}"""

    val snapshotJson = SnapshotConverter.fromIndex(index, savedAt)!!
    val decisions = JSONObject(snapshotJson).getJSONArray("decisions")

    assertEquals(3, decisions.length())
    decisions.getJSONObject(0).let {
      assertEquals("scrutin_public", it.getString("voteMode"))
      val c = it.getJSONObject("count")
      assertEquals(listOf(503, 0, 67), listOf(c.getInt("pour"), c.getInt("contre"), c.getInt("abstentions")))
      // Format fixé de l'instantané : sans `nonVotants`.
      assertEquals(3, c.length())
      assertEquals(false, c.has("nonVotants"))
    }
    decisions.getJSONObject(1).let {
      assertEquals("main_levee", it.getString("voteMode"))
      assertEquals(false, it.has("count"))
    }
    // Décompte malformé : omis, la décision reste.
    assertEquals(false, decisions.getJSONObject(2).has("count"))

    val parsed = DecisionSnapshot.parse(snapshotJson)!!.decisions
    assertEquals(VoteCount(503, 0, 67), parsed[0].count)
    assertEquals(VoteMode.SCRUTIN_PUBLIC, parsed[0].voteMode)
    assertEquals(VoteArc.Dotted(ArcColor.POUR), parsed[1].arc)
    assertEquals(VoteArc.Solid(ArcColor.POUR), parsed[2].arc)
  }

  @Test
  fun refuse_une_autre_version_ou_un_index_illisible() {
    assertNull(SnapshotConverter.fromIndex("""{"schemaVersion":2,"decisions":[]}""", savedAt))
    assertNull(SnapshotConverter.fromIndex("pas du json", savedAt))
  }

  @Test
  fun le_widget_relit_l_instantane() {
    val index = """{"schemaVersion":1,"decisions":[${decision(8716)}]}"""
    val parsed = DecisionSnapshot.parse(SnapshotConverter.fromIndex(index, savedAt))!!
    assertEquals("VTANR5L17V8716", parsed.decisions.single().id)
    assertEquals(VoteResult.ADOPTE, parsed.decisions.single().result)
  }
}
