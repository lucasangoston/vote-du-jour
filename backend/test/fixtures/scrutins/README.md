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
| 7349 | l’article unique (retenu depuis #22, comme résolution) | adopté | référence de dossier législatif |

Ajoutés pour le ticket #7 (titre court et étape) :

| Scrutin | Catégorie | Particularité |
| --- | --- | --- |
| 289 | l'ensemble (CMP) | rattaché par le titre d'un document du dossier |
| 504 | l'ensemble (deuxième lecture) | |
| 1194 | l'ensemble (première lecture) | ni `dossierRef` ni `voteRef` : rattaché par l'intitulé |
| 4696 | l'ensemble (nouvelle lecture) | |
| 4758 | l'ensemble (lecture définitive) | |
| 6346 | l'ensemble (CMP) | rattaché par `dossierRef` seulement |

Ajoutés pour le ticket #8 (textes adoptés à main levée) :

| Scrutin | Catégorie | Particularité |
| --- | --- | --- |
| 1011 | l'article 2 (non retenu) | texte adopté ensuite à main levée le même jour (DLR5L16N49852) |
| 2633 | l'article unique (retenu depuis #22) | vaut vote sur l'ensemble : le texte (DLR5L16N47676) n'est pas adopté à main levée, bien que son acte de décision ne cite aucun scrutin |
| 2900 | l'ensemble (première lecture) | non rattaché à son dossier (DLR5L17N52002, intitulé « … de la collectivité de Corse ») : écarte le doublon à main levée par l'intitulé |

Ajoutés pour le ticket #22 (article unique), même archive téléchargée le
17/10/2026 (`articleUniqueNumeros` dans `test/fixtures.dart`, hors de
`fixtureNumeros`) :

| Scrutin | Catégorie | Particularité |
| --- | --- | --- |
| 684 | l'article unique (proposition de résolution européenne) | ensemble voté à part le même jour (685) : non publié |
| 685 | l'ensemble de la proposition de résolution européenne | |
| 691 | l'article unique (proposition de résolution européenne, Mercosur) | non rattaché ; 685 le même jour porte sur un autre texte : publié |
| 930 | l'article unique (proposition de loi) | ensemble voté à part le même jour (931) : non publié |
| 931 | l'ensemble de la proposition de loi | |
| 1333 | l'article unique (projet de loi) | rejeté : le texte est rejeté |
| 6902 | l'article unique (projet de loi, deuxième lecture) | ensemble voté en scrutin solennel une semaine plus tard (7260) : non publié |
| 7260 | l'ensemble du projet de loi (deuxième lecture) | scrutin solennel |

Ajoutés pour le ticket #10 (détection en direct), archive téléchargée le
18/10/2026 (hors de `fixtureNumeros`) :

| Scrutin | Catégorie | Particularité |
| --- | --- | --- |
| 8705 | la proposition de loi (première lecture) | scrutin solennel ; aussi lu sur le site (`../site/`) |
| 8706 | la proposition de loi organique (première lecture) | idem : provisoire puis confirmé |

Ajoutés pour le ticket #67 (arc dans l'ordre de l'hémicycle), archive
téléchargée le 23/10/2026 (hors de `fixtureNumeros`) :

| Scrutin | Catégorie | Particularité |
| --- | --- | --- |
| 8610 | la proposition de résolution | rejetée : la gauche et le centre contre, DR, UDR et RN pour |
| 8611 | la proposition de résolution | rejetée : DR partagé (9 pour, 5 abstentions, 1 contre) |

`../titres_non_classes.csv` : les 47 intitulés réels que la règle initiale du
PRD ne classait pas (numéro, date, code du type de vote, sort, titre), produits
par le spike #15 (outil jetable, supprimé depuis ; voir PR #16)
sur le même jeu de données.
