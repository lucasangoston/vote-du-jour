# vote-du-jour

Widget iOS et Android qui résume les décisions votées à l'Assemblée nationale : un titre court, une phrase d'explication et le résultat (adopté ou rejeté). Un tap ouvre le détail de la décision dans l'app.

Nom de travail : le nom définitif de l'app n'est pas encore choisi.

Données : open data de l'Assemblée nationale (Licence Ouverte Etalab).

## Configuration

- Données publiées : `https://pub-51ad28220f184398acec4e2b145afd20.r2.dev` (bucket R2 `vote-du-jour`, domaine r2.dev réservé au développement).
- Identifiant de l'app (iOS et Android) : `com.lucasangoston.votedujour`.
- Team ID Apple : `792WRWDFHZ`.
- Secrets GitHub Actions : `R2_ACCOUNT_ID`, `R2_BUCKET`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `ANTHROPIC_API_KEY`.
- Variables GitHub Actions : `R2_PUBLIC_BASE_URL`, `APPLE_TEAM_ID`, `APP_ID`.

## Structure

```
packages/vote_contract/  contrat de données partagé (Dart pur) : DecisionIndex, schemaVersion, chemin v1/latest.json
backend/                 job Dart planifié : téléchargement conditionnel, lecture du dump, sélection des décisions, publication
app/                     app Flutter (iOS, Android ; cible web pour le développement)
.github/workflows/       ci.yml (tests) et publish.yml (job horaire + lancement manuel)
tools/                   outils ponctuels (spikes)
```

Le job et l'app dépendent du contrat par chemin relatif (`path: ../packages/vote_contract`), sans workspace : chaque paquet se résout seul, et le job tourne en CI avec le seul SDK Dart.

Données publiées dans le bucket :

- `v1/latest.json` : les 50 dernières décisions, de la plus récente à la plus ancienne (format décrit dans `packages/vote_contract/README.md`). Un changement cassant du format publiera sous `v2/`.
- `state/scrutins-dump.json` : état du job (`Last-Modified` du dernier jeu de données traité).
- `state/dossiers.json` : `Last-Modified` du jeu de données des dossiers législatifs et index qui en est tiré (titres, actes citant chaque scrutin, adoptions sans scrutin), réutilisé tant que ce jeu de données ne change pas. Son format est versionné : un cache d'une ancienne version est reconstruit.

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

## App

```bash
cd app
flutter pub get
flutter test
flutter run                                         # lit l'URL publique R2
flutter run --dart-define=DATA_BASE_URL=http://localhost:8765   # autre source (dossier publié en local, par exemple)
```

Cibles minimales : iOS 17, Android 10 (API 29).
