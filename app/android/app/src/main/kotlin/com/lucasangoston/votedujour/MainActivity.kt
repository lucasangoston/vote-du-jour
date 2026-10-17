package com.lucasangoston.votedujour

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
  /**
   * Garde le dernier lien reçu comme intent de l'activité. Quand le système a tué le processus
   * mais garde la tâche, un tap sur le widget recrée l'activité avec son intent d'origine puis
   * livre le lien du widget par `onNewIntent`, avant que Dart n'écoute les taps :
   * `HomeWidget.initiallyLaunchedFromHomeWidget()`, qui lit l'intent de l'activité, retrouve
   * alors le lien et l'app ouvre le détail de la décision.
   */
  override fun onNewIntent(intent: Intent) {
    setIntent(intent)
    super.onNewIntent(intent)
  }
}
