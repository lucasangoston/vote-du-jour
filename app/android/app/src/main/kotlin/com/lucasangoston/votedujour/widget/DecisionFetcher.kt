package com.lucasangoston.votedujour.widget

import android.content.Context
import android.util.Log
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/**
 * Télécharge `v1/latest.json` sans l'app et le convertit en instantané du widget (même format que
 * `lib/src/home_widget/widget_snapshot.dart`), écrit dans les préférences de home_widget. En cas
 * d'échec, l'instantané précédent est gardé : le widget affiche les dernières données connues.
 */
object DecisionFetcher {
  /** URL publique compilée, si l'app n'en a pas partagé une autre (`--dart-define`). */
  const val DEFAULT_BASE_URL = "https://pub-51ad28220f184398acec4e2b145afd20.r2.dev"

  /** Clé écrite par l'app (`lib/src/home_widget/widget_data_source.dart`). */
  const val BASE_URL_KEY = "data_base_url"

  /** Préférences de home_widget (`HomeWidgetPlugin.PREFERENCES`), lues par le widget Glance. */
  private const val PREFERENCES = "HomeWidgetPreferences"
  private const val INDEX_PATH = "v1/latest.json"
  private const val TAG = "DecisionFetcher"

  /** Renvoie `true` si un nouvel instantané a été écrit. */
  suspend fun refresh(context: Context): Boolean =
      withContext(Dispatchers.IO) {
        val prefs = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val baseUrl =
            prefs.getString(BASE_URL_KEY, null)?.takeIf { it.isNotBlank() } ?: DEFAULT_BASE_URL
        try {
          val body = download(indexUrl(baseUrl))
          // Sièges de la dernière décision (#78), seule dessinée en hémicycle : ceux de
          // l'instantané précédent pour la même décision, sinon ceux de son fichier de détail (un
          // téléchargement par nouvelle décision).
          val seats =
              SnapshotConverter.latestDecisionId(body)?.let { id ->
                val previous =
                    DecisionSnapshot.parse(prefs.getString(DecisionSnapshot.STORAGE_KEY, null))
                        ?.decisions
                        ?.firstOrNull { it.id == id }
                        ?.seats
                (previous ?: detailSeats(baseUrl, id))?.let { mapOf(id to it) }
              }
          val snapshot =
              SnapshotConverter.fromIndex(body, Instant.now(), seats.orEmpty())
                  ?: return@withContext false
          prefs.edit().putString(DecisionSnapshot.STORAGE_KEY, snapshot).commit()
        } catch (e: Exception) {
          Log.w(TAG, "Rafraîchissement impossible, instantané précédent gardé : $e")
          false
        }
      }

  fun indexUrl(baseUrl: String): String = "${baseUrl.trimEnd('/')}/$INDEX_PATH"

  /** Fichier de détail d'une décision (`v1/decisions/<id>.json`), pour ses sièges. */
  fun detailUrl(baseUrl: String, id: String): String =
      "${baseUrl.trimEnd('/')}/v1/decisions/${java.net.URLEncoder.encode(id, "UTF-8")}.json"

  /** Sièges du fichier de détail ; `null` en cas d'échec : le widget dessine l'arc. */
  private fun detailSeats(baseUrl: String, id: String): SeatVotes? =
      try {
        SeatVotes.fromDetail(download(detailUrl(baseUrl, id)), id)
      } catch (e: Exception) {
        Log.w(TAG, "Sièges de $id indisponibles : $e")
        null
      }

  private fun download(url: String): String {
    val connection = URL(url).openConnection() as HttpURLConnection
    try {
      connection.connectTimeout = 15_000
      connection.readTimeout = 15_000
      val status = connection.responseCode
      if (status != HttpURLConnection.HTTP_OK) error("HTTP $status")
      return connection.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
    } finally {
      connection.disconnect()
    }
  }
}

/**
 * Conversion fidèle de l'index publié (contrat `vote_contract`, version 1) vers l'instantané lu par
 * le widget, comme `WidgetSnapshot.fromIndex` côté Dart : les trois décisions lisibles les plus
 * récentes, titre = titre du résumé, sinon `shortTitle`, sinon `officialTitle` (avec majuscule
 * initiale), étape = `stage`, explication = phrase du résumé (#9), mode de vote et décompte
 * (`count`) pour l'arc du vote (#29).
 */
object SnapshotConverter {
  private const val SCHEMA_VERSION = 1
  private const val SNAPSHOT_VERSION = 1
  private const val MAX_DECISIONS = 3
  private const val MAX_UPCOMING_VOTES = 3
  private const val VOTE_SOLENNEL = "vote_solennel"

  private val TYPES =
      setOf(
          "ensemble",
          "motion_de_censure",
          "declaration_gouvernement",
          "rejet_prealable",
          "premiere_partie_budget",
          "resolution",
          "autre",
      )
  private val STATUSES = setOf("provisoire", "confirmee")
  private val RESULTS = setOf("adopte", "rejete")
  private const val SCRUTIN_PUBLIC = "scrutin_public"
  private const val MAIN_LEVEE = "main_levee"

  /** Mention du mode de vote (`lib/src/vote_mode_label.dart`). */
  private const val MAIN_LEVEE_LABEL = "à main levée"

  /** Mention d'une décision pas encore confirmée (`lib/src/decision_status_label.dart`). */
  private const val PROVISIONAL_LABEL = "provisoire"

  /**
   * `null` si l'index est illisible ou d'une autre version de schéma. [seats] donne les sièges de
   * l'hémicycle (#78) des décisions qui en ont, par identifiant.
   */
  fun fromIndex(json: String, savedAt: Instant, seats: Map<String, SeatVotes> = emptyMap()): String? {
    val items = decisions(json) ?: return null
    val root = JSONObject(json)
    val decisions = JSONArray()
    for (i in 0 until items.length()) {
      if (decisions.length() == MAX_DECISIONS) break
      items
          .optJSONObject(i)
          ?.let(::convert)
          ?.also { d -> seats[d.getString("id")]?.let { d.put("seats", it.encoded) } }
          ?.let(decisions::put)
    }
    val snapshot =
        JSONObject()
            .put("version", SNAPSHOT_VERSION)
            .put("savedAt", savedAt.truncatedTo(ChronoUnit.MILLIS).toString())
            .put("decisions", decisions)
    // Prochains votes solennels (#56), comme `WidgetSnapshot.fromIndex` : les trois plus proches,
    // champ omis s'il n'y en a pas.
    val upcoming = root.optJSONArray("upcoming")
    val votes =
        (0 until (upcoming?.length() ?: 0))
            .mapNotNull { i -> upcoming?.optJSONObject(i)?.let(::convertUpcoming) }
            .sortedBy { it.startsAt }
            .take(MAX_UPCOMING_VOTES)
    if (votes.isNotEmpty()) {
      snapshot.put("upcomingVotes", JSONArray(votes.map { it.toJson() }))
    }
    return snapshot.toString()
  }

  /**
   * Identifiant de la décision la plus récente que les widgets afficheront, `null` si l'index est
   * illisible ou n'en a pas.
   */
  fun latestDecisionId(json: String): String? {
    val items = decisions(json) ?: return null
    return (0 until items.length()).firstNotNullOfOrNull { i ->
      items.optJSONObject(i)?.let(::convert)?.getString("id")
    }
  }

  private fun decisions(json: String): JSONArray? {
    val root =
        try {
          JSONObject(json)
        } catch (e: Exception) {
          return null
        }
    if (root.opt("schemaVersion") != SCHEMA_VERSION) return null
    return root.optJSONArray("decisions")
  }

  /**
   * Vote solennel du bloc `upcoming`, mêmes règles que `UpcomingItem.tryFromJson` : un point
   * malformé ou d'une autre nature (discussion) est ignoré.
   */
  private fun convertUpcoming(u: JSONObject): UpcomingVote? {
    val id = u.opt("id") as? String ?: return null
    if (u.opt("kind") != VOTE_SOLENNEL) return null
    val startsAt = UpcomingVote.instant(u.opt("startsAt") as? String) ?: return null
    if (u.opt("seanceRef") !is String || u.opt("label") !is String) return null
    val title = optionalString(u, "shortTitle")?.trim() ?: return null
    return UpcomingVote(id, startsAt, title.replaceFirstChar { it.uppercase() })
  }

  /** Mêmes règles que `DecisionSummary.tryFromJson` : une décision malformée est ignorée. */
  private fun convert(d: JSONObject): JSONObject? {
    val id = d.opt("id") as? String ?: return null
    // `voteMode` absent : scrutin public (index antérieurs au ticket #8).
    val voteMode =
        if (d.isNull("voteMode")) SCRUTIN_PUBLIC
        else (d.opt("voteMode") as? String)?.takeIf { it == SCRUTIN_PUBLIC || it == MAIN_LEVEE }
            ?: return null
    // `numero` n'est exigé que pour un scrutin public (absent à main levée).
    val numero = if (d.isNull("numero")) null else d.opt("numero")
    if (numero != null && numero !is Int && numero !is Long) return null
    if (numero == null && voteMode == SCRUTIN_PUBLIC) return null
    // `status` absent : confirmée (champ optionnel depuis le ticket #10).
    val status = if (d.isNull("status")) "confirmee" else d.opt("status") as? String
    if ((d.opt("type") as? String) !in TYPES || status !in STATUSES) {
      return null
    }
    val result = (d.opt("result") as? String)?.takeIf { it in RESULTS } ?: return null
    val date =
        try {
          LocalDate.parse(d.opt("date") as? String ?: return null)
        } catch (e: Exception) {
          return null
        }
    val officialTitle = d.opt("officialTitle") as? String ?: return null
    if (d.opt("sourceUrl") !is String) return null
    val shortTitle = optionalString(d, "shortTitle")
    val summary = plainSummary(d.optJSONObject("summary"))
    // Même règle que `WidgetDecision.fromSummary` : les mentions « à main levée »
    // et « provisoire » s'ajoutent à l'étape, que le widget affiche déjà.
    val mentions =
        listOfNotNull(
                MAIN_LEVEE_LABEL.takeIf { voteMode == MAIN_LEVEE },
                PROVISIONAL_LABEL.takeIf { status == "provisoire" },
            )
            .joinToString(" · ")
    val stage =
        optionalString(d, "stage").let { stage ->
          when {
            mentions.isEmpty() -> stage
            stage != null -> "$stage · $mentions"
            else -> mentions.replaceFirstChar { it.uppercase() }
          }
        }
    val out =
        JSONObject()
            .put("id", id)
            .put("result", result)
            .put("date", date.toString())
            .put(
                "title",
                (summary?.first ?: shortTitle ?: officialTitle).trim().replaceFirstChar {
                  it.uppercase()
                },
            )
    stage?.let { out.put("stage", it) }
    // Phrase du résumé, affichée par le widget moyen.
    summary?.second?.let { out.put("explanation", it.trim()) }
    // Arc du vote (#29) : mode de vote et décompte (`nonVotants` ignoré). Un décompte malformé est
    // omis, la décision reste lisible.
    out.put("voteMode", voteMode)
    VoteCount.parse(d.optJSONObject("count"))?.let { out.put("count", it.toJson()) }
    // Arc dans l'ordre de l'hémicycle (#67) : un arc malformé est ignoré, le widget dessine alors
    // l'arc par sens.
    HemicyclePart.parseList(d.optJSONArray("arc"))?.let { out.put("arc", HemicyclePart.toJson(it)) }
    return out
  }

  /**
   * Titre et phrase du résumé, mêmes règles que `PlainSummary.tryFromJson` : un résumé malformé
   * est ignoré (la décision reste lisible). Le titre est le titre court du résumé (#72) s'il est
   * valide, sinon son titre (`compactTitle`).
   */
  private fun plainSummary(s: JSONObject?): Pair<String, String>? {
    if (s == null) return null
    val title = optionalString(s, "title") ?: return null
    val explanation = optionalString(s, "explanation") ?: return null
    val version = s.opt("promptVersion")
    if (version !is Int && version !is Long) return null
    val short = optionalString(s, "shortTitle")?.takeIf { it.length <= SHORT_TITLE_MAX_LENGTH }
    return (short ?: title) to explanation
  }

  /** Même borne que `shortTitleMaxLength` du contrat. */
  private const val SHORT_TITLE_MAX_LENGTH = 35

  private fun optionalString(d: JSONObject, key: String): String? =
      (d.opt(key) as? String)?.takeIf { it.isNotBlank() }
}
