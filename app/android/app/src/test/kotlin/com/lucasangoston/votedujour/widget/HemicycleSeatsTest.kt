package com.lucasangoston.votedujour.widget

import java.time.Instant
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Sièges de l'hémicycle des widgets (#78) : lecture du détail, instantané, géométrie. */
class HemicycleSeatsTest {
  private fun detail(seats: String, id: String = "VTANR5L17V8706") =
      """{"schemaVersion":1,"decision":{"id":"$id"},"seats":$seats}"""

  @Test
  fun detail_vers_instantane() {
    val votes =
        SeatVotes.fromDetail(
            detail("""[[1,"PO1","p"],[5,"PO2","c"],[3,"PO1","a"],[6,"PO3","n"],[7,"PO3","x"]]"""),
            "VTANR5L17V8706",
        )!!
    assertEquals("p-a-cnx", votes.encoded)
    assertEquals(votes, SeatVotes.parse(votes.encoded))
    assertEquals(SeatVote.CONTRE, votes.byPlace[5])
  }

  @Test
  fun detail_illisible_ou_d_une_autre_decision() {
    assertNull(SeatVotes.fromDetail(detail("""[[1,"PO1","p"]]"""), "autre"))
    assertNull(
        SeatVotes.fromDetail("""{"schemaVersion":2,"decision":{"id":"a"},"seats":[[1,"P","p"]]}""", "a"))
    assertNull(SeatVotes.fromDetail("pas du json", "a"))
    listOf(
            "[]",
            "null",
            """[[1,"PO1","z"]]""",
            """[[0,"PO1","p"]]""",
            """[[1,"PO1","p"],[1,"PO2","c"]]""",
            """[[1,"","p"]]""",
            """[[1.5,"PO1","p"]]""",
            """[[true,"PO1","p"]]""",
            """[[1,"PO1"]]""",
            """[[1,"PO1","pp"]]""",
        )
        .forEach { assertNull(it, SeatVotes.fromDetail(detail(it), "VTANR5L17V8706")) }
  }

  @Test
  fun instantane_illisible() {
    assertNull(SeatVotes.parse(null))
    assertNull(SeatVotes.parse(""))
    assertNull(SeatVotes.parse("---"))
    assertNull(SeatVotes.parse("ppz"))
    assertNull(SeatVotes.parse(42))
    assertNull(SeatVotes.parse("p".repeat(1001)))
  }

  @Test
  fun geometrie_du_plan() {
    assertEquals(582, HemicycleGeometry.PLACES.size)
    assertEquals(582, HemicycleGeometry.XS.size)
    assertEquals(582, HemicycleGeometry.YS.size)
    assertArrayEquals(HemicycleGeometry.PLACES.sortedArray(), HemicycleGeometry.PLACES)
    assertEquals(582, HemicycleGeometry.PLACES.toSet().size)
    HemicycleGeometry.XS.zip(HemicycleGeometry.YS).forEach { (x, y) ->
      assertTrue(x in HemicycleGeometry.VIEW_X..HemicycleGeometry.VIEW_X + HemicycleGeometry.VIEW_WIDTH)
      assertTrue(y in HemicycleGeometry.VIEW_Y..HemicycleGeometry.VIEW_Y + HemicycleGeometry.VIEW_HEIGHT)
    }
    // Place 1 à droite du centre, la dernière à l'extrême gauche (vu du perchoir).
    assertEquals(1, HemicycleGeometry.PLACES.first())
    assertEquals(159.79f, HemicycleGeometry.XS.first())
    assertEquals(650, HemicycleGeometry.PLACES.last())
    assertEquals(HemicycleGeometry.XS.min(), HemicycleGeometry.XS.last())
  }

  @Test
  fun disposition_par_vote() {
    // Place 3 sans député ; la place 4 n'existe pas sur le plan : rien n'est dessiné.
    val layout = HemicycleLayout.of(SeatVotes.parse("pc-xanx")!!)
    assertEquals(5, layout.count)
    assertArrayEquals(floatArrayOf(159.79f, 117.92f), layout.dots[SeatKind.POUR], 0f)
    assertEquals(1, layout.dots[SeatKind.CONTRE]!!.size / 2)
    assertEquals(1, layout.dots[SeatKind.ABSTENTION]!!.size / 2)
    assertEquals(2, layout.dots[SeatKind.OFF]!!.size / 2)
    // Les estompés dessous.
    assertEquals(SeatKind.OFF, layout.dots.keys.first())
    assertEquals(0.5f, SeatKind.ABSTENTION.radiusScale)
  }

  @Test
  fun exemple_de_8706() {
    val layout = HemicycleLayout.of(SeatVotes.parse(HemicycleGeometry.SAMPLE_VOTES)!!)
    assertEquals(574, layout.count)
    assertEquals(503, layout.dots[SeatKind.POUR]!!.size / 2)
    assertNull(layout.dots[SeatKind.CONTRE])
    assertEquals(67, layout.dots[SeatKind.ABSTENTION]!!.size / 2)
  }

  @Test
  fun resolution_des_masques_plafonnee() {
    // Petit widget, écran 2,75 : plafonné à 2 px par dp.
    assertEquals(2f, HemicycleRenderer.scale(142f, 79f, 3, 2.75f))
    // Écran peu dense : sa densité.
    assertEquals(1f, HemicycleRenderer.scale(142f, 79f, 3, 1f))
    // Grand widget, quatre calques : sous le budget de pixels.
    val s = HemicycleRenderer.scale(328f, 183f, 4, 2.75f)
    assertTrue(s < 2f)
    assertTrue(328f * s * 183f * s * 4 <= HemicycleRenderer.PIXEL_BUDGET + 1)
  }

  @Test
  fun sieges_de_la_derniere_decision_dans_l_instantane() {
    fun decision(numero: Int, type: String = "ensemble") =
        """{"id":"VTANR5L17V$numero","numero":$numero,"type":"$type","status":"confirmee",
        "result":"adopte","date":"2026-10-13","officialTitle":"t",
        "sourceUrl":"https://exemple.test/$numero"}"""
    val index =
        """{"schemaVersion":1,"decisions":[${decision(8714, "inconnu")},${decision(8713)},${decision(8712)}]}"""
    // La première décision lisible, celle que les widgets dessinent.
    assertEquals("VTANR5L17V8713", SnapshotConverter.latestDecisionId(index))
    assertNull(SnapshotConverter.latestDecisionId("{}"))
    val votes = SeatVotes.parse("pc-a")!!
    val json =
        SnapshotConverter.fromIndex(index, Instant.EPOCH, mapOf("VTANR5L17V8713" to votes))!!
    val decisions = JSONObject(json).getJSONArray("decisions")
    assertEquals("pc-a", decisions.getJSONObject(0).getString("seats"))
    assertTrue(!decisions.getJSONObject(1).has("seats"))
    val snapshot = DecisionSnapshot.parse(json)!!
    assertEquals(votes, snapshot.decisions[0].seats)
    assertNull(snapshot.decisions[1].seats)
  }

  @Test
  fun sieges_illisibles_dans_l_instantane() {
    val json =
        JSONObject()
            .put("version", 1)
            .put(
                "decisions",
                JSONArray()
                    .put(
                        JSONObject()
                            .put("id", "a")
                            .put("result", "adopte")
                            .put("date", "2026-10-13")
                            .put("title", "T")
                            .put("seats", "ppz")))
            .toString()
    val snapshot = DecisionSnapshot.parse(json)!!
    assertEquals(1, snapshot.decisions.size)
    assertNull(snapshot.decisions[0].seats)
  }

  @Test
  fun url_du_detail() {
    assertEquals(
        "https://exemple.test/v1/decisions/VTANR5L17V8706.json",
        DecisionFetcher.detailUrl("https://exemple.test/", "VTANR5L17V8706"),
    )
  }

  @Test
  fun libelles_du_prochain_vote() {
    val vote = UpcomingVote("v", Instant.parse("2026-11-03T14:00:00Z"), "Budget de l'État 2027")
    assertEquals("Vote · mar. 15 h", vote.whenLabel)
    assertEquals(
        "Prochain vote solennel, mar. 3 nov. à 15 h. Budget de l'État 2027",
        vote.accessibilityLabel,
    )
    assertEquals("21 h 30", UpcomingVote("w", Instant.parse("2026-07-01T19:30:00Z"), "T").timeLabel)
  }
}
