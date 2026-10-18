package com.lucasangoston.votedujour.widget

import android.content.Context
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import java.time.Duration
import java.time.LocalDate
import java.time.ZonedDateTime
import java.util.concurrent.TimeUnit

/**
 * Rafraîchit le widget sans l'app : télécharge les dernières décisions (sauf pour le redessin de
 * minuit), puis redessine le widget pour recalculer la date relative.
 */
class DecisionRefreshWorker(context: Context, params: WorkerParameters) :
    CoroutineWorker(context, params) {

  override suspend fun doWork(): Result {
    val redrawOnly = inputData.getBoolean(KEY_REDRAW_ONLY, false)
    if (!redrawOnly) DecisionFetcher.refresh(applicationContext)
    redrawWidgets(applicationContext)
    // Le redessin de minuit se reprogramme pour le lendemain ; la tâche horaire le réarme aussi.
    DecisionRefreshScheduler.scheduleMidnightRedraw(
        applicationContext,
        if (redrawOnly) ExistingWorkPolicy.APPEND_OR_REPLACE else ExistingWorkPolicy.REPLACE,
    )
    // Un échec réseau n'est pas réessayé : la prochaine exécution horaire s'en charge.
    return Result.success()
  }

  companion object {
    const val KEY_REDRAW_ONLY = "redraw_only"

    /** Redessine les widgets posés, toutes tailles confondues. */
    suspend fun redrawWidgets(context: Context) {
      val manager = GlanceAppWidgetManager(context)
      DecisionWidgets.all().forEach { widget ->
        manager.getGlanceIds(widget.javaClass).forEach { id ->
          // Comme home_widget : toucher l'état force Glance à recomposer avec les préférences à jour.
          updateAppWidgetState(context, HomeWidgetGlanceStateDefinition(), id) { it }
          widget.update(context, id)
        }
      }
    }
  }
}

/**
 * Programmation WorkManager : une tâche périodique d'une heure (le minimum autorisé est 15 min ;
 * Android peut la retarder en mode économie d'énergie), avec réseau, et un redessin juste après
 * minuit pour que « Aujourd'hui » devienne « Hier » à l'heure.
 */
object DecisionRefreshScheduler {
  const val PERIODIC_WORK = "decision_widget_refresh"
  const val MIDNIGHT_WORK = "decision_widget_midnight"

  fun schedule(context: Context) {
    val request =
        PeriodicWorkRequestBuilder<DecisionRefreshWorker>(1, TimeUnit.HOURS)
            .setConstraints(
                Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
            )
            .build()
    WorkManager.getInstance(context)
        .enqueueUniquePeriodicWork(PERIODIC_WORK, ExistingPeriodicWorkPolicy.KEEP, request)
    scheduleMidnightRedraw(context, ExistingWorkPolicy.REPLACE)
  }

  fun cancel(context: Context) {
    WorkManager.getInstance(context).apply {
      cancelUniqueWork(PERIODIC_WORK)
      cancelUniqueWork(MIDNIGHT_WORK)
    }
  }

  fun scheduleMidnightRedraw(context: Context, policy: ExistingWorkPolicy) {
    val now = ZonedDateTime.now()
    val nextMidnight = LocalDate.now(now.zone).plusDays(1).atStartOfDay(now.zone).plusMinutes(1)
    val request =
        OneTimeWorkRequestBuilder<DecisionRefreshWorker>()
            .setInitialDelay(Duration.between(now, nextMidnight))
            .setInputData(workDataOf(DecisionRefreshWorker.KEY_REDRAW_ONLY to true))
            .build()
    WorkManager.getInstance(context).enqueueUniqueWork(MIDNIGHT_WORK, policy, request)
  }
}
