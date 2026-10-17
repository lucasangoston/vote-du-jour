# Spike #15 : délai de publication des scrutins

Outil jetable, indépendant du paquet backend. Il répond à deux questions du PRD (#1) :

1. Combien de temps après un vote le scrutin apparaît-il sur le site de l'Assemblée, puis dans le jeu de données quotidien ?
2. Le filtrage par début de titre (ensemble, motion, déclaration du Gouvernement) est-il fiable sur tout l'historique ?

## Commandes

```bash
cd tools/spike_delai
dart pub get

# Un passage de mesure (ce que fait le cron) : 1 GET de la liste du site
# (50 derniers scrutins, 1 ou 2 pages de plus seulement en cas de débordement)
# et 1 GET conditionnel (If-Modified-Since) sur le dump.
dart run bin/spike_delai.dart releve <dossier-donnees>

# Synthèse lisible des mesures du dossier.
dart run bin/spike_delai.dart resume <dossier-donnees>

# Fiabilité du filtrage sur une archive Scrutins.json.zip.
dart run bin/spike_delai.dart filtrage Scrutins.json.zip resultats/titres_non_classes.csv

dart test
```

## Mesure en continu

Le workflow `.github/workflows/spike-delai.yml` lance `releve` toutes les 5 minutes, du lundi au vendredi, de 9 h à minuit (heure de Paris), puis commite le dossier de données sur la branche `spike-data` :

- `releve.csv` : un scrutin par ligne. `apparition_site_utc` est le premier passage où il a été vu ; il est apparu entre `passage_precedent_utc` et cet instant. `apparition_dump_utc` est le Last-Modified du premier dump qui le contient ; `date_scrutin` vient du dump.
- `passages.csv` : un passage par ligne, pour connaître la cadence réelle du cron (GitHub retarde souvent les crons planifiés) et les erreurs.
- `etat.json` : numéro de référence (les scrutins antérieurs au premier passage sont ignorés) et Last-Modified du dump.
- `heures_vote.csv` : à remplir à la main (`numero,heure_vote_paris`, par exemple `8901,2026-10-20 16:42`) avec l'heure du vote lue dans le compte rendu de séance, pour quelques scrutins.
- `resume.md` : synthèse régénérée à chaque passage (cadence, délai vote vers site, délai site vers dump, heures d'apparition).

Le User-Agent `vote-du-jour-spike/0.1` identifie l'outil auprès du site.
