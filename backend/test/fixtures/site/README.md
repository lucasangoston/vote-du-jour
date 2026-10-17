# Fixtures : pages réelles du site de l'Assemblée

Pages enregistrées sans modification le 18/10/2026 (ticket #10), avec le
User-Agent du job. Source : Assemblée nationale, https://www.assemblee-nationale.fr.

| Fichier | URL | Contenu |
| --- | --- | --- |
| `liste_scrutins.html` | `/dyn/17/scrutins?limit=50` | la page lue par la détection en direct : scrutins 8828 à 8877 (séance budgétaire du 16/10/2026), amendements et articles, aucune décision |
| `liste_scrutins_solennels.html` | `/dyn/17/scrutins?typeScrutin=SPS&limit=20` | 8705 et 8706, votes sur l'ensemble adoptés le 13/10/2026 (même intitulé que le jeu de données) |
| `liste_motions_censure.html` | `/dyn/17/scrutins?typeScrutin=MOC&limit=10` | 7 motions de censure rejetées : seules les voix pour sont affichées |
| `scrutin_8706.html` | `/dyn/17/scrutins/8706` | page d'un scrutin (même synthèse que la liste, plus le vote par député) |

Les scrutins 8705 et 8706 du jeu de données correspondant sont dans
`../scrutins/`.
