package com.lucasangoston.votedujour.widget

import org.junit.Assert.assertEquals
import org.junit.Test

/** Règles de l'arc du vote (charte Hémicycle, #29). */
class VoteArcTest {
  private fun arc(pour: Int, contre: Int, abstentions: Int, result: VoteResult = VoteResult.ADOPTE) =
      VoteArc.of(result, VoteCount(pour, contre, abstentions), mainLevee = false)

  private fun VoteArc.layers() = (this as VoteArc.Segmented).layers

  @Test
  fun pour_puis_abstentions_puis_contre_proportionnels_aux_exprimes() {
    val layers = arc(pour = 144, contre = 199, abstentions = 5, VoteResult.REJETE).layers()

    assertEquals(listOf(ArcColor.POUR, ArcColor.ABSTENTION, ArcColor.CONTRE), layers.map { it.color })
    assertEquals(0.0, layers[0].start, 1e-9)
    assertEquals(144.0 / 348, layers[1].start, 1e-9)
    assertEquals(149.0 / 348, layers[2].start, 1e-9)
  }

  @Test
  fun une_portion_vide_n_est_pas_dessinee() {
    val layers = arc(pour = 503, contre = 0, abstentions = 67).layers()

    assertEquals(listOf(ArcColor.POUR, ArcColor.ABSTENTION), layers.map { it.color })
    // 88,2 % de pour, comme la maquette.
    assertEquals(0.882, layers[1].start, 0.001)
  }

  @Test
  fun unanimite_contre() {
    val layers = arc(pour = 0, contre = 12, abstentions = 0, VoteResult.REJETE).layers()
    assertEquals(listOf(ArcLayer(ArcColor.CONTRE, 0.0)), layers)
  }

  @Test
  fun main_levee_pointilles_couleur_du_resultat() {
    assertEquals(
        VoteArc.Dotted(ArcColor.POUR),
        VoteArc.of(VoteResult.ADOPTE, count = null, mainLevee = true),
    )
    // Même avec un décompte : la main levée l'emporte.
    assertEquals(
        VoteArc.Dotted(ArcColor.CONTRE),
        VoteArc.of(VoteResult.REJETE, VoteCount(1, 2, 3), mainLevee = true),
    )
  }

  @Test
  fun sans_decompte_arc_plein_couleur_du_resultat() {
    assertEquals(VoteArc.Solid(ArcColor.POUR), VoteArc.of(VoteResult.ADOPTE, null, false))
    assertEquals(VoteArc.Solid(ArcColor.CONTRE), VoteArc.of(VoteResult.REJETE, null, false))
    // Décompte à zéro : rien à répartir.
    assertEquals(
        VoteArc.Solid(ArcColor.CONTRE),
        VoteArc.of(VoteResult.REJETE, VoteCount(0, 0, 0), false),
    )
  }

  @Test
  fun grands_nombres_sans_debordement() {
    val max = Int.MAX_VALUE
    val layers = arc(pour = max, contre = max, abstentions = 0).layers()
    assertEquals(0.5, layers[1].start, 1e-9)
  }

  @Test
  fun points_reguliers_avec_un_point_a_chaque_extremite() {
    assertEquals(listOf(0.0, 0.25, 0.5, 0.75, 1.0), VoteArc.dotPositions(5))
    assertEquals(listOf(0.5), VoteArc.dotPositions(1))
    assertEquals(emptyList<Double>(), VoteArc.dotPositions(0))
  }
}
