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
          val snapshot = SnapshotConverter.fromIndex(body, Instant.now()) ?: return@withContext false
          prefs.edit().putString(DecisionSnapshot.STORAGE_KEY, snapshot).commit()
        } catch (e: Exception) {
          Log.w(TAG, "Rafraîchissement impossible, instantané précédent gardé : $e")
          false
        }
      }

  fun indexUrl(baseUrl: String): String = "${baseUrl.trimEnd('/')}/$INDEX_PATH"

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
 * récentes, titre = `shortTitle` sinon `officialTitle` (avec majuscule initiale), étape = `stage`.
 */
object SnapshotConverter {
  private const val SCHEMA_VERSION = 1
  private const val SNAPSHOT_VERSION = 1
  private const val MAX_DECISIONS = 3

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

  /** `null` si l'index est illisible ou d'une autre version de schéma. */
  fun fromIndex(json: String, savedAt: Instant): String? {
    val root =
        try {
          JSONObject(json)
        } catch (e: Exception) {
          return null
        }
    if (root.opt("schemaVersion") != SCHEMA_VERSION) return null
    val items = root.optJSONArray("decisions") ?: return null
    val decisions = JSONArray()
    for (i in 0 until items.length()) {
      if (decisions.length() == MAX_DECISIONS) break
      items.optJSONObject(i)?.let(::convert)?.let(decisions::put)
    }
    return JSONObject()
        .put("version", SNAPSHOT_VERSION)
        .put("savedAt", savedAt.truncatedTo(ChronoUnit.MILLIS).toString())
        .put("decisions", decisions)
        .toString()
  }

  /** Mêmes règles que `DecisionSummary.tryFromJson` : une décision malformée est ignorée. */
  private fun convert(d: JSONObject): JSONObject? {
    val id = d.opt("id") as? String ?: return null
    val numero = d.opt("numero")
    if (numero !is Int && numero !is Long) return null
    if ((d.opt("type") as? String) !in TYPES || (d.opt("status") as? String) !in STATUSES) {
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
    val stage = optionalString(d, "stage")
    val out =
        JSONObject()
            .put("id", id)
            .put("result", result)
            .put("date", date.toString())
            .put("title", (shortTitle ?: officialTitle).trim().replaceFirstChar { it.uppercase() })
    stage?.let { out.put("stage", it) }
    return out
  }

  private fun optionalString(d: JSONObject, key: String): String? =
      (d.opt(key) as? String)?.takeIf { it.isNotBlank() }
}
