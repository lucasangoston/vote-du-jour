# Fixtures : scrutins réels

Fichiers extraits sans modification de l'archive officielle
`Scrutins.json.zip` (17e législature, téléchargée le 17/10/2026) :
https://data.assemblee-nationale.fr/static/openData/repository/17/loi/scrutins/Scrutins.json.zip

Source : Assemblée nationale, open data. Licence Ouverte / Open Licence (Etalab).

| Scrutin | Catégorie | Résultat | Particularité |
| --- | --- | --- | --- |
| 217 | l'ensemble (proposition de loi) | rejeté | apostrophes ’ dans le corps du titre |
| 519 | motion de censure | adopté | type de vote « motion de censure » |
| 1018 | l'ensemble de la proposition de résolution | adopté | apostrophe droite |
| 2278 | l’ensemble (proposition de loi) | adopté | titre commençant par « l’ » |
| 2372 | sous-amendement | rejeté | |
| 2873 | motion de rejet préalable | adopté | |
| 3022 | l’amendement | rejeté | titre commençant par « l’ » |
| 3054 | déclaration de politique générale du Gouvernement | rejeté | scrutin solennel |
| 4241 | première partie du projet de loi de finances | rejeté | scrutin solennel, non retenu |
| 4802 | déclaration du Gouvernement (art. 50-1) | adopté | scrutin solennel |
| 5731 | motion de censure | rejeté | |
| 7349 | l’article unique | adopté | référence de dossier législatif |

Ajoutés pour le ticket #7 (titre court et étape) :

| Scrutin | Catégorie | Particularité |
| --- | --- | --- |
| 289 | l'ensemble (CMP) | rattaché par le titre d'un document du dossier |
| 504 | l'ensemble (deuxième lecture) | |
| 1194 | l'ensemble (première lecture) | ni `dossierRef` ni `voteRef` : rattaché par l'intitulé |
| 4696 | l'ensemble (nouvelle lecture) | |
| 4758 | l'ensemble (lecture définitive) | |
| 6346 | l'ensemble (CMP) | rattaché par `dossierRef` seulement |

`../titres_non_classes.csv` : les 47 intitulés réels que la règle initiale du
PRD ne classait pas (numéro, date, code du type de vote, sort, titre), produits
par le spike #15 (`tools/spike_delai`, branche `spike/15-delai-publication`)
sur le même jeu de données.
