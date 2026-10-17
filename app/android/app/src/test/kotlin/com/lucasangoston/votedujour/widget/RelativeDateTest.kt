package com.lucasangoston.votedujour.widget

import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Test

class RelativeDateTest {
  private val vendredi = LocalDate.of(2026, 10, 16)

  @Test
  fun aujourdhuiPuisHierAMinuit() {
    assertEquals("Aujourd'hui", RelativeDate.label(vendredi, today = vendredi))
    assertEquals("Hier", RelativeDate.label(vendredi, today = LocalDate.of(2026, 10, 17)))
  }

  @Test
  fun compteLesJoursDeCalendrierWeekEndCompris() {
    assertEquals("Il y a 2 jours", RelativeDate.label(vendredi, today = LocalDate.of(2026, 10, 18)))
    assertEquals("Il y a 3 jours", RelativeDate.label(vendredi, today = LocalDate.of(2026, 10, 19)))
    assertEquals("Il y a 6 jours", RelativeDate.label(vendredi, today = LocalDate.of(2026, 10, 22)))
  }

  @Test
  fun auDelaDeSixJoursLaDateComplete() {
    assertEquals("16 octobre 2026", RelativeDate.label(vendredi, today = LocalDate.of(2026, 10, 23)))
    assertEquals(
        "1er septembre 2026",
        RelativeDate.label(LocalDate.of(2026, 9, 1), today = LocalDate.of(2026, 10, 17)),
    )
  }

  @Test
  fun changementDAnneeEtDateFuture() {
    assertEquals("Hier", RelativeDate.label(LocalDate.of(2026, 12, 31), LocalDate.of(2027, 1, 1)))
    assertEquals("Aujourd'hui", RelativeDate.label(vendredi, today = LocalDate.of(2026, 10, 15)))
  }
}
