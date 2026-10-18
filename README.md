# vote-du-jour

Widget iOS et Android qui résume les décisions votées à l'Assemblée nationale : un titre court, une phrase d'explication et le résultat (adopté ou rejeté). Un tap ouvre le détail de la décision dans l'app.

Nom de travail : le nom définitif de l'app n'est pas encore choisi.

Données : open data de l'Assemblée nationale (Licence Ouverte Etalab).

## Configuration

- Données publiées : `https://pub-51ad28220f184398acec4e2b145afd20.r2.dev` (bucket R2 `vote-du-jour`, domaine r2.dev réservé au développement).
- Identifiant de l'app (iOS et Android) : `com.lucasangoston.votedujour`.
- Team ID Apple : `792WRWDFHZ`.
- Secrets GitHub Actions : `R2_ACCOUNT_ID`, `R2_BUCKET`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `ANTHROPIC_API_KEY`, `FCM_SERVICE_ACCOUNT` (clé JSON du compte de service Firebase, notifications push ; facultatif).
- Variables GitHub Actions : `R2_PUBLIC_BASE_URL`, `APPLE_TEAM_ID`, `APP_ID`.

## Structure

```
packages/vote_contract/  contrat de données partagé (Dart pur) : DecisionIndex, schemaVersion, chemin v1/latest.json
backend/                 job Dart planifié : téléchargement conditionnel, lecture du dump, sélection des décisions, publication
app/                     app Flutter (iOS, Android ; cible web pour le développement)
.github/workflows/       ci.yml (tests), publish.yml (job horaire + lancement manuel) et live.yml (détection en direct)
tools/                   outils ponctuels (spikes)
```

Le job et l'app dépendent du contrat par chemin relatif (`path: ../packages/vote_contract`), sans workspace : chaque paquet se résout seul, et le job tourne en CI avec le seul SDK Dart.

Données publiées dans le bucket :

- `v1/latest.json` : les 50 dernières décisions, de la plus récente à la plus ancienne (format décrit dans `packages/vote_contract/README.md`). Un changement cassant du format publiera sous `v2/`.
- `v1/decisions/<id>.json` : le détail de chaque décision de l'index (décompte, vote par groupe ; format dans `packages/vote_contract/README.md`). Seuls les fichiers dont le contenu a changé sont réécrits.
- `state/scrutins-dump.json` : état du job (`Last-Modified` du dernier jeu de données traité).
- `state/scrutins-confirmes.json` : scrutins du dernier jeu de données utiles à l'index (retenus ou sur l'article unique), sans vote par groupe, et dernier numéro du jeu de données. Écrit par le job, relu par la détection en direct pour reconstruire l'index sans retélécharger l'archive.
- `state/live.json` : état de la détection en direct (scrutins provisoires en attente du jeu de données, dernier numéro vu sur le site).
- `state/dossiers.json` : `Last-Modified` du jeu de données des dossiers législatifs et index qui en est tiré (titres, actes citant chaque scrutin, adoptions sans scrutin, texte déposé de chaque dossier), réutilisé tant que ce jeu de données ne change pas. Son format est versionné : un cache d'une ancienne version est reconstruit.
- `state/resumes.json` : cache des résumés, par décision (résumé, source, texte, modèle ; ou « à régénérer » avec la raison et le nombre d'échecs ; ou abandonné).
- `state/notifications.json` : décisions déjà notifiées (identifiant → date d'envoi, ou `initial` pour celles déjà publiées à la mise en service).
- `state/organes.json` : `Last-Modified` du jeu de données des acteurs et organes (AMO20, ~3 Mo) et noms des groupes politiques qui en sont tirés. Un nouveau jeu de données ne fait republier les détails que si les noms des groupes ont changé.

## Job de publication

```bash
cd backend
dart pub get
dart test

# Publication dans un dossier local (build/publish par défaut) :
dart run bin/vote_job.dart                       # télécharge le jeu de données s'il a changé
dart run bin/vote_job.dart --dump-file Scrutins.json.zip   # à partir d'une archive déjà téléchargée
dart run bin/vote_job.dart --dump-file Scrutins.json.zip --dossiers-file Dossiers_Legislatifs.json.zip
dart run bin/vote_job.dart --force               # retraite même si rien n'a changé

# Publication sur R2 (variables R2_ACCOUNT_ID, R2_BUCKET, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY) :
dart run bin/vote_job.dart --store=r2
```

Le workflow `publish.yml` lance le job toutes les heures ; il peut aussi être lancé à la main (Actions > Publication des décisions > Run workflow, option « force »). Une exécution sans nouveau jeu de données s'arrête sur une réponse 304, sans rien réécrire.

Un scrutin sur l'article unique d'un texte vaut vote sur l'ensemble : il est publié comme tel (type `ensemble`, ou `resolution` pour une proposition de résolution), sauf si l'ensemble du même texte est ensuite voté à part dans la même lecture, auquel cas seul ce dernier vote est publié.

Les textes adoptés à main levée viennent aussi des dossiers législatifs : un acte de décision de l'Assemblée en séance (`AN…-DEBATS-DEC`, `CMP-DEBATS-AN-DEC`), au statut d'adoption, qui ne cite aucun scrutin (`voteRefs`), et sans scrutin public retenu ni scrutin sur l'article unique du même texte le même jour. Ils sont publiés avec `voteMode: main_levee`, sans numéro ni décompte.

Le titre court et l'étape de la procédure viennent du jeu de données des dossiers législatifs (`Dossiers_Legislatifs.json.zip`, ~10 Mo), lui aussi téléchargé seulement s'il a changé. De nouveaux dossiers font retraiter les scrutins ; s'ils sont indisponibles, le job publie quand même avec le dernier index connu (ou des libellés tirés des intitulés).

## Résumés (Claude Haiku 5.5)

À chaque exécution horaire (`publish.yml`), que le jeu de données ait changé ou non, le job résume les décisions de l'index qui ne le sont pas encore : un titre lisible, une phrase d'explication et 3 ou 4 points sur ce que dit le texte. Modèle `claude-haiku-5-5`, API Messages appelée en HTTP (`backend/lib/src/summary/`), sortie structurée (schéma JSON). La consigne, avec ses règles de neutralité, est versionnée dans `backend/lib/src/summary/summary_prompt.dart` (`summaryPromptVersion`, enregistré dans chaque résumé).

- Texte source : le texte déposé à l'Assemblée (premier acte `AN…-DEPOT` du dossier), lu sur `https://www.assemblee-nationale.fr/dyn/opendata/<uid>.html` : son exposé des motifs, sinon ses articles (texte transmis par le Sénat), tronqué à 24 000 caractères. Les motions de censure et déclarations du Gouvernement sont résumées sur leur intitulé, sans points. Le texte est isolé entre balises `<texte_source>` et traité comme une donnée.
- Un texte pas encore en ligne (HTTP 404), une décision provisoire pas encore rattachée à son dossier ou un échec du modèle marquent la décision « à régénérer » : elle est publiée avec son titre court officiel et retentée aux passages suivants. Un texte toujours introuvable 14 jours après le vote est résumé sur son intitulé ; après 3 échecs du modèle, la décision est abandonnée.
- Coût borné : un seul appel par décision (cache `state/resumes.json`, résumé repris sans appel pour un autre vote sur le même texte), au plus 15 appels et 5 décisions « à régénérer » retentées par passage.
- Le passage en direct (`live.yml`) n'appelle pas le modèle : il applique les résumés du cache. Une décision provisoire est résumée au passage horaire suivant.
- Sans `ANTHROPIC_API_KEY`, le job publie sans nouveau résumé (les résumés existants restent publiés). La clé n'existe que dans les secrets GitHub : en local, le job ne résume rien.

## Détection en direct

Pendant les séances, le job lit la liste des 50 derniers scrutins du site de l'Assemblée (`https://www.assemblee-nationale.fr/dyn/17/scrutins?limit=50`, un GET par passage, User-Agent `vote-du-jour/1.0`), plus la page d'un nouveau scrutin seulement si la liste n'en donne pas le sort. Les scrutins plus récents que le jeu de données passent par le même sélecteur et le même rattachement aux dossiers ; ceux qui sont retenus sont publiés avec `status: provisoire`. Le jeu de données du lendemain les confirme (`status: confirmee`, même `id`) ; un scrutin provisoire qu'il ne contient pas encore reste publié comme provisoire.

```bash
cd backend
dart run bin/vote_job.dart --live                    # dans les plages seulement (lun.-ven., 9h-24h, heure de Paris)
dart run bin/vote_job.dart --live --ignore-window    # tout de suite
dart run bin/vote_job.dart --live --live-days=1-5 --live-hours=9-24
dart run bin/vote_job.dart --live --store=r2
```

Le workflow `live.yml` lance un passage toutes les 10 minutes. Les plages se règlent en tête du fichier (`LIVE_DAYS`, `LIVE_HOURS`, en heure de Paris, vérifiées par le job) ; le cron, en UTC, doit les englober en heure d'été comme en heure d'hiver. Il partage le groupe de concurrence `publish` avec `publish.yml` : jamais deux publications simultanées.

Si le site est illisible (panne, structure changée), le passage s'arrête sans rien écrire et l'erreur apparaît en avertissement dans GitHub Actions ; le jeu de données continue d'être publié par `publish.yml`. Le site ne donne ni le type de vote (le garde-fou des scrutins solennels ne s'applique qu'avec le jeu de données), ni le dossier, ni le vote par groupe.

## Notifications push des votes importants

Après la publication et les résumés, chaque exécution de `publish.yml` envoie une notification au sujet Firebase Cloud Messaging `votes-importants` pour chaque nouvelle décision importante (`backend/lib/src/notifications/`) :

- vote important : scrutin public solennel (`typeVote` `SPS`, lu dans `state/scrutins-confirmes.json`), motion de censure, ou texte en lecture définitive ou texte de compromis (CMP), adopté ou rejeté ;
- jamais : vote à main levée, proposition de résolution, décision provisoire (notifiée à sa confirmation par le jeu de données, pour ne jamais annoncer un résultat faux), décision de plus de 7 jours ;
- message : titre « Adopté : <titre> » ou « Rejeté : <titre> » (titre du résumé, sinon titre court), corps = phrase d'explication (sinon l'étape), données `decisionId` et `link` (`votedujour://decisions/<id>`), son par défaut sur Android et iOS ;
- au plus 3 envois par passage, les plus anciennes d'abord ; les suivantes partent au passage suivant (une heure plus tard) ;
- mémoire `state/notifications.json`, écrite après chaque envoi réussi : une décision n'est jamais notifiée deux fois ; un envoi en échec est retenté au passage suivant. Au premier passage, les décisions déjà publiées sont marquées sans envoi.
- Envoi par l'API FCM HTTP v1 : jeton OAuth2 obtenu avec un JWT RS256 signé par la clé du compte de service. Sans le secret `FCM_SERVICE_ACCOUNT`, la fonction est désactivée (une ligne dans le journal) ; un échec d'envoi est journalisé en avertissement sans faire échouer l'exécution. Le passage en direct (`live.yml`) n'envoie jamais de notification.

## App

```bash
cd app
flutter pub get
flutter test
flutter run                                         # lit l'URL publique R2
flutter run --dart-define=DATA_BASE_URL=http://localhost:8765   # autre source (dossier publié en local, par exemple)
```

Cibles minimales : iOS 17, Android 10 (API 29).

### Hors ligne et rafraîchissement des widgets

- L'app garde le dernier `latest.json` téléchargé (dossier de support de l'app) et l'affiche avant de rafraîchir : sans connexion, la liste montre les dernières données connues.
- Les widgets se rafraîchissent sans l'app, en téléchargeant eux-mêmes `v1/latest.json` (URL partagée par l'app dans l'espace des widgets, sinon l'URL publique compilée) et en le convertissant au format de l'instantané (`lib/src/home_widget/widget_snapshot.dart`). En cas d'échec, ils gardent l'instantané précédent.
  - iOS : la timeline WidgetKit (`ios/DecisionWidget/DecisionTimeline.swift`) télécharge au plus une fois par quart d'heure, se recharge au bout d'une heure (dans la limite du budget de WidgetKit) et contient une entrée à minuit pour la date relative.
  - Android : WorkManager (`DecisionRefreshWorker.kt`), programmé à l'ajout du widget : une tâche toutes les heures avec réseau, et un redessin juste après minuit.
- Les dates sont relatives (« Aujourd'hui », « Hier », « Il y a 3 jours », puis la date complète), en jours de calendrier dans le fuseau du téléphone, avec les mêmes règles en Dart, Swift et Kotlin.

Vérifier le rafraîchissement sans ouvrir l'app :

```bash
# Android (build debug) : lancer le worker tout de suite (WorkManager refuse d'avancer la tâche périodique)
adb shell am broadcast -n com.lucasangoston.votedujour/.widget.DebugRefreshReceiver
adb shell am broadcast -n com.lucasangoston.votedujour/.widget.DebugRefreshReceiver --ez redraw_only true   # redessin seul (minuit)
adb shell cmd connectivity airplane-mode enable    # hors ligne : le widget garde l'instantané
adb logcat -s DecisionFetcher                      # échecs de téléchargement
adb shell dumpsys jobscheduler | grep -A3 DecisionRefreshWorker   # tâches programmées

# Tests natifs
(cd android && ./gradlew :app:testDebugUnitTest)
(cd ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:RunnerTests)
# + téléchargement réel vers le groupe d'apps : préfixer par TEST_RUNNER_VDJ_NETWORK_TESTS=1
```
