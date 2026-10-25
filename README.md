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
```

Le job et l'app dépendent du contrat par chemin relatif (`path: ../packages/vote_contract`), sans workspace : chaque paquet se résout seul, et le job tourne en CI avec le seul SDK Dart.

Données publiées dans le bucket :

- `v1/latest.json` : les 50 dernières décisions, de la plus récente à la plus ancienne (format décrit dans `packages/vote_contract/README.md`). Un changement cassant du format publiera sous `v2/`.
- `v1/latest.json` contient aussi le bloc optionnel `upcoming` : l'ordre du jour des prochains jours (#52), et le bloc optionnel `inDebate` : le texte en débat et ses articles votés au scrutin public (#55).
- `v1/decisions/<id>.json` : le détail de chaque décision de l'index (décompte, vote par groupe, sièges du scrutin ; format dans `packages/vote_contract/README.md`). Seuls les fichiers dont le contenu a changé sont réécrits.
- `state/scrutins-dump.json` : état du job (`Last-Modified` du dernier jeu de données traité).
- `state/scrutins-confirmes.json` : scrutins du dernier jeu de données utiles à l'index (retenus ou sur l'article unique), sans vote par groupe, et dernier numéro du jeu de données. Écrit par le job, relu par la détection en direct pour reconstruire l'index sans retélécharger l'archive.
- `state/live.json` : état de la détection en direct (scrutins provisoires en attente du jeu de données, dernier numéro vu sur le site).
- `state/dossiers.json` : `Last-Modified` du jeu de données des dossiers législatifs et index qui en est tiré (titres, actes citant chaque scrutin, adoptions sans scrutin, texte déposé de chaque dossier), réutilisé tant que ce jeu de données ne change pas. Son format est versionné : un cache d'une ancienne version est reconstruit.
- `state/resumes.json` : cache des résumés, par décision et par texte en débat (résumé, source, texte, modèle ; ou « à régénérer » avec la raison et le nombre d'échecs ; ou abandonné).
- `state/notifications.json` : décisions déjà notifiées (identifiant → date d'envoi, ou `initial` pour celles déjà publiées à la mise en service) et, sous `eve`, votes solennels déjà annoncés la veille (« séance dossier » → date d'envoi, oubliés après 30 jours), sous `debates`, textes déjà annoncés en débat (dossier → date d'envoi, jamais oubliés).
- `state/arguments.json` : état des arguments (#35) : `Last-Modified` de la dernière archive des comptes rendus lue, et par décision rattachée : arguments faits (avec la version de la consigne et le compte rendu), en attente d'appel, ou abandonnés.
- `state/agenda.json` : `ETag` de la dernière archive de l'agenda lue et points retenus de l'ordre du jour des séances pas finies depuis plus de 7 jours (#52, #55), relus quand l'agenda n'a pas changé.
- `state/articles.json` : votes sur les articles (et amendements de suppression adoptés) des 30 derniers jours du dernier jeu de données des scrutins, avec dossier et séance, et dernier numéro du jeu de données (#55). Écrit par le job, relu par les passages de l'agenda et en direct.
- `state/organes.json` : `Last-Modified` du jeu de données des acteurs et organes (AMO20, ~3 Mo) et l'annuaire qui en est tiré (nom et couleur des groupes politiques, place de chaque député). Un nouveau jeu de données ne fait republier les détails que si l'annuaire a changé.

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

- Texte source : le texte déposé à l'Assemblée (premier acte `AN…-DEPOT` du dossier), lu sur `https://www.assemblee-nationale.fr/dyn/opendata/<uid>.html` : son exposé des motifs, sinon ses articles (texte transmis par le Sénat) ; pour un texte budgétaire (PLF, PLFSS), qui a un exposé par article, le plan du texte (intitulés des parties et des articles) ; tronqué à 24 000 caractères. Les motions de censure et déclarations du Gouvernement sont résumées sur leur intitulé, sans points. Le texte est isolé entre balises `<texte_source>` et traité comme une donnée.
- Un texte pas encore en ligne (HTTP 404), une décision provisoire pas encore rattachée à son dossier ou un échec du modèle marquent la décision « à régénérer » : elle est publiée avec son titre court officiel et retentée aux passages suivants. Un texte toujours introuvable 14 jours après le vote est résumé sur son intitulé ; après 3 échecs du modèle, la décision est abandonnée.
- Coût borné : un seul appel par décision (cache `state/resumes.json`, résumé repris sans appel pour un autre vote sur le même texte), au plus 15 appels et 5 décisions « à régénérer » retentées par passage.
- Le passage en direct (`live.yml`) n'appelle pas le modèle : il applique les résumés du cache. Une décision provisoire est résumée au passage horaire suivant.
- Sans `ANTHROPIC_API_KEY`, le job publie sans nouveau résumé (les résumés existants restent publiés). La clé n'existe que dans les secrets GitHub : en local, le job ne résume rien.

## Arguments pour et contre (#35)

Après les résumés, le job tire des explications de vote des groupes les arguments pour, contre et d'abstention de chaque vote sur l'ensemble (ou sur l'article unique, ou sur une proposition de résolution), publiés dans le fichier de détail (`arguments`, format dans `packages/vote_contract/README.md`). Code : `backend/lib/src/arguments/`.

- Source : comptes rendus de séance, open data AN (`syseron.xml.zip`, ~59 Mo, XML Syceron, publiés ~2 jours après la séance), téléchargés seulement s'ils ont changé (`If-Modified-Since`), et seulement si une décision attend des arguments. Seuls les comptes rendus des jours concernés sont analysés.
- Rattachement prudent : une décision confirmée est rattachée à la section « Explications de vote » (ou « … communes ») suivie du « Vote sur l'ensemble » du même jour qui nomme le même texte (phrase « Je mets aux voix… », sinon titre du vote ou de la discussion), même nature (loi organique ou non, résolution ou non) et mêmes voix pour et contre quand le compte rendu les donne. Un rattachement qui n'est pas unique dans les deux sens est abandonné : en cas de doute, rien. Une section commune à deux textes vaut pour les deux. Des explications sur une motion de rejet, suivies de la discussion, ne sont jamais rattachées au vote final.
- Chaque intervention est classée selon la position, dans le scrutin, du groupe de l'orateur (sigle écrit après son nom) ; interruptions, présidence, didascalies, non-inscrits et orateurs sans groupe sont ignorés.
- Modèle : le même que les résumés, consigne dédiée versionnée dans `backend/lib/src/arguments/arguments_prompt.dart` (`argumentsPromptVersion`) : 2 à 3 arguments par camp présent, chacun attribué à un groupe de ce camp qui l'a réellement dit, rien d'ajouté, ton neutre, une phrase courte. Seules les explications de vote sont envoyées, entre balises `<explications_de_vote>`, au plus 6 000 caractères par groupe. Sortie structurée (schéma JSON limitant chaque camp à ses groupes) ; une réponse qui attribue un argument à un autre groupe, est vide, trop longue ou mal formée est rejetée en entier.
- Coût borné : au plus 5 appels par passage ; une décision faite pour la version courante de la consigne n'est plus jamais redemandée (`state/arguments.json`) ; après 3 réponses rejetées, elle est abandonnée. Le passage en direct n'en rédige pas, et le job republie les arguments de l'état quand il reconstruit les fichiers de détail.
- Votes sans explications de vote (main levée, petits textes, conventions) : pas de champ `arguments`.
- Sans `ANTHROPIC_API_KEY`, aucun nouvel argument (ceux de l'état restent publiés).

## Détection en direct

Pendant les séances, le job lit la liste des 50 derniers scrutins du site de l'Assemblée (`https://www.assemblee-nationale.fr/dyn/17/scrutins?page=1&limit=50`, un GET par passage d'ordinaire, User-Agent `vote-du-jour/1.0`). Si cette page ne contient que des scrutins jamais vus (son plus ancien est au-delà du suivant du dernier scrutin connu, dans `state/live.json` ou le jeu de données), il lit la page suivante après une pause de 30 s (le `Crawl-delay` du robots.txt du site), jusqu'à 4 pages (200 scrutins) ; au-delà, les scrutins manquants sont signalés et arrivent avec le jeu de données. Il lit aussi la page d'un nouveau scrutin seulement si la liste n'en donne pas le sort. Les scrutins plus récents que le jeu de données passent par le même sélecteur et le même rattachement aux dossiers ; ceux qui sont retenus sont publiés avec `status: provisoire`. Le jeu de données du lendemain les confirme (`status: confirmee`, même `id`) ; un scrutin provisoire qu'il ne contient pas encore reste publié comme provisoire.

```bash
cd backend
dart run bin/vote_job.dart --live                    # dans les plages seulement (lun.-ven., 9h-24h, heure de Paris)
dart run bin/vote_job.dart --live --ignore-window    # tout de suite
dart run bin/vote_job.dart --live --live-days=1-5 --live-hours=9-24
dart run bin/vote_job.dart --live --store=r2
```

Le workflow `live.yml` lance un passage toutes les 10 minutes. Les plages se règlent en tête du fichier (`LIVE_DAYS`, `LIVE_HOURS`, en heure de Paris, vérifiées par le job) ; le cron, en UTC, doit les englober en heure d'été comme en heure d'hiver. Il partage le groupe de concurrence `publish` avec `publish.yml` : jamais deux publications simultanées.

Si le site est illisible (panne, structure changée), le passage s'arrête sans rien écrire et l'erreur apparaît en avertissement dans GitHub Actions ; le jeu de données continue d'être publié par `publish.yml`. Le site ne donne ni le type de vote (le garde-fou des scrutins solennels ne s'applique qu'avec le jeu de données), ni le dossier, ni le vote par groupe.

## Ordre du jour : « À venir » (#52)

Après la publication, chaque exécution de `publish.yml` lit l'agenda officiel (`Agenda.json.zip`, ~8,5 Mo, téléchargé seulement s'il a changé : `If-None-Match` avec l'`ETag` de `state/agenda.json`) et publie dans `v1/latest.json` le bloc `upcoming` (format dans `packages/vote_contract/README.md`). Code : `backend/lib/src/agenda/`.

- Séances publiques de l'Assemblée seulement (uid `RUAN…`, organe `PO838901`), séance et point « Confirmé » : un point reporté passe à « Supprimé » et disparaît au passage suivant.
- Points « Discussion » et « Suite de la discussion » d'un texte, sur 7 jours ; « Vote solennel » et « Vote par scrutin public », sur 14 jours (le vote d'un texte budgétaire tombe souvent au-delà d'une semaine). Un point par texte et par nature : plusieurs séances de discussion du même texte n'en font qu'un, « en cours » si la première n'est qu'une suite.
- Dossier : celui de l'ordre du jour, sinon retrouvé par le texte nommé dans le libellé (« Vote solennel sur le projet de loi… » ↔ « Suite de la discussion du projet de loi… » d'un autre point), seulement s'il est unique.
- Titre court sans appel au modèle : titre (du résumé, sinon court) de la dernière décision publiée du même dossier, sinon titre du dossier (`state/dossiers.json`), sinon libellé sans formule de procédure.
- Heure : début de la séance (l'agenda ne donne pas l'heure du point). Le point reste à venir jusqu'à la fin de la séance (`timeStampFin`, sinon 6 heures après le début).
- Panne de l'agenda : avertissement, bloc recalculé avec le dernier agenda connu (ou laissé tel quel au premier passage) ; les décisions sont publiées normalement. Le job et le passage en direct (`live.yml`) republient l'index avec le bloc déjà publié, sans lire l'agenda.

```bash
cd backend
dart run bin/vote_job.dart --agenda-file Agenda.json.zip   # agenda déjà téléchargé
```

## Texte en débat : « En débat » (#55)

Le passage de l'agenda publie aussi dans `v1/latest.json` le bloc `inDebate` (format dans `packages/vote_contract/README.md`). Code : `backend/lib/src/agenda/in_debate.dart`.

- Texte : dossier du point « Discussion » ou « Suite de la discussion » de la séance de l'Assemblée en cours ou de la dernière, commencée dans les 7 derniers jours ; si la séance en inscrit plusieurs, celui dont un article a été voté en dernier, sinon le premier. Aucun texte : pas de bloc.
- Articles : scrutins du dossier (`objet.dossierLegislatif`) dont l'intitulé commence par « l'article… » (adopté ou rejeté), et amendements « … de suppression de l'article N » adoptés (article supprimé). Les autres amendements, les amendements de suppression rejetés et l'article unique (vote sur l'ensemble) sont exclus. Même lecture que le dernier vote ; un article par numéro (son dernier vote), du plus récent au plus ancien. Les votes à main levée ne sont pas connus.
- Détection en direct : les articles de la liste du site plus récents que le jeu de données (sans dossier) sont rattachés au texte en débat par le texte nommé dans l'intitulé ; le bloc publié les garde jusqu'à ce que le jeu de données les confirme.
- Titre court : même règle que « À venir ».
- Résumé (#73, `inDebate.summary`) : rédigé par le passage du résumeur du job horaire, avant les décisions et dans le même plafond d'appels, à partir du texte déposé du dossier (même consigne qu'une décision). Un seul appel par texte (cache `state/resumes.json`, entrée `en_debat:<dossier>`), repris sans appel par la décision sur l'ensemble du texte ; le passage de l'agenda et la détection en direct appliquent le résumé du cache. Sans texte exploitable (pas de dépôt connu, texte pas encore en ligne), pas de résumé : retenté aux passages suivants, jamais sur l'intitulé seul.

## Notifications push des votes importants

Après la publication et les résumés, chaque exécution de `publish.yml` envoie une notification au sujet Firebase Cloud Messaging `votes-importants` pour chaque nouvelle décision importante (`backend/lib/src/notifications/`) :

- vote important : scrutin public solennel (`typeVote` `SPS`, lu dans `state/scrutins-confirmes.json`), motion de censure, ou texte en lecture définitive ou texte de compromis (CMP), adopté ou rejeté ;
- jamais : vote à main levée, proposition de résolution, décision provisoire (notifiée à sa confirmation par le jeu de données, pour ne jamais annoncer un résultat faux), décision de plus de 7 jours ;
- message : titre « Adopté : <titre> » ou « Rejeté : <titre> » (titre du résumé, sinon titre court), corps = phrase d'explication (sinon l'étape), données `decisionId` et `link` (`votedujour://decisions/<id>`), son par défaut sur Android et iOS ;
- au plus 3 envois par passage, les plus anciennes d'abord ; les suivantes partent au passage suivant (une heure plus tard) ;
- mémoire `state/notifications.json`, écrite après chaque envoi réussi : une décision n'est jamais notifiée deux fois ; un envoi en échec est retenté au passage suivant. Au premier passage, les décisions déjà publiées sont marquées sans envoi.
- Envoi par l'API FCM HTTP v1 : jeton OAuth2 obtenu avec un JWT RS256 signé par la clé du compte de service. Sans le secret `FCM_SERVICE_ACCOUNT`, la fonction est désactivée (une ligne dans le journal) ; un échec d'envoi est journalisé en avertissement sans faire échouer l'exécution. Le passage en direct (`live.yml`) n'envoie jamais de notification.

Le même passage annonce, la veille au soir, les votes solennels du lendemain (#54, `eve_notification.dart`) :

- passage dont l'heure de Paris est entre 18h et 23h59, point « Vote solennel » du bloc `upcoming` dont la séance a lieu le lendemain (heure de Paris) ;
- état relu juste avant : le bloc vient d'être recalculé par le passage de l'agenda (seuls les points « Confirmé » y sont ; un point supprimé ou déplacé n'y est plus à cette date). Si l'agenda n'a pas pu être relu à ce passage, aucune annonce (un passage suivant de la soirée s'en charge) ;
- message : titre « Vote solennel demain », corps « À partir de 15h : <titre court> » (heure de Paris du début de la séance), données `upcomingId` et `link` (`votedujour://decisions`, la liste) ;
- une annonce par séance et dossier, avant les décisions, sous le même plafond de 3 envois par passage ; au premier passage, les points déjà à venir sont marqués sans envoi ;
- limite : le cron de GitHub est irrégulier (#51) ; sans aucun passage entre 18h et minuit, l'annonce n'est pas envoyée (jamais le jour même).

Il annonce aussi le texte qui passe en séance (#77, `debate_notification.dart`), d'après le bloc `inDebate` :

- le jour de la séance (heure de Paris), une fois celle-ci commencée ; un texte repéré un jour suivant n'est pas annoncé ;
- résumé du texte présent (`inDebate.summary`), pour un titre court lisible et un écran complet à l'ouverture ; sans résumé à 18h (heure de Paris), l'annonce part quand même avec le titre court du bloc ;
- message : titre « En débat aujourd’hui », corps « <titre court> : les députés examinent le texte. » (titre court du résumé, sinon celui du bloc), données `dossierRef` et `link` (`votedujour://en-debat/<dossier>`, l'écran « En débat » de l'app) ;
- une seule annonce par texte (dossier), jamais oubliée : la suite de la discussion ne rappelle pas le texte ; mémoire `debates` de `state/notifications.json` ; après les annonces de la veille et avant les décisions, sous le même plafond ; au premier passage, le texte déjà en débat est marqué sans envoi.

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
