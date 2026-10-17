package com.lucasangoston.votedujour.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf

/**
 * Debug uniquement : lance tout de suite une exécution de [DecisionRefreshWorker], sans ouvrir
 * l'app. WorkManager refuse d'avancer une tâche périodique (`cmd jobscheduler run -f` est ignoré
 * avant la fin de la période), d'où ce déclencheur pour les vérifications manuelles :
 * ```
 * adb shell am broadcast -n com.lucasangoston.votedujour/.widget.DebugRefreshReceiver
 * adb shell am broadcast -n com.lucasangoston.votedujour/.widget.DebugRefreshReceiver --ez redraw_only true
 * ```
 */
class DebugRefreshReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val redrawOnly = intent.getBooleanExtra(DecisionRefreshWorker.KEY_REDRAW_ONLY, false)
    val request =
        OneTimeWorkRequestBuilder<DecisionRefreshWorker>()
            .setInputData(workDataOf(DecisionRefreshWorker.KEY_REDRAW_ONLY to redrawOnly))
            .build()
    WorkManager.getInstance(context).enqueue(request)
  }
}
