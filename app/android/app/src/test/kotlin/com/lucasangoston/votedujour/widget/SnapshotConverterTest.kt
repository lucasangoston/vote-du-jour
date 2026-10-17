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
