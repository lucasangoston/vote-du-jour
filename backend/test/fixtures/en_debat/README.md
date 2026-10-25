# Fixtures : texte en débat (ticket #55)

Fichiers extraits sans modification des archives officielles téléchargées le
21/10/2026 au soir (17e législature) :

- `Agenda.json.zip` : https://data.assemblee-nationale.fr/static/openData/repository/17/vp/reunions/Agenda.json.zip
- `Scrutins.json.zip` : https://data.assemblee-nationale.fr/static/openData/repository/17/loi/scrutins/Scrutins.json.zip

Source : Assemblée nationale, open data. Licence Ouverte / Open Licence (Etalab).

## `reunion/` : séances passées

Ajoutées aux réunions de `../agenda/` par
`fixtureAgendaArchive(withPastSeances: true)` (`test/fixtures.dart`).

| Réunion | Date (Paris) | Ordre du jour |
| --- | --- | --- |
| RUANR5L17S2027IDS30949 | ven. 16/10 21 h 30 | suite de la discussion du PLF 2027, 1re partie (`DLR5L17N54629`) |
| RUANR5L17S2027IDS30950 | lun. 19/10 15 h | débat sur les finances locales (sans dossier) ; suite du PLF |
| RUANR5L17S2027IDS30951 | lun. 19/10 21 h 30 | suite du PLF |
| RUANR5L17S2027IDS30953 | mar. 20/10 21 h 30 | discussion du PLFSS 2027 (`DLR5L17N54951`) |
| RUANR5L17S2027IDS30955 | mer. 21/10 14 h | questions au Gouvernement ; suite du PLFSS |

## `scrutins/` : votes sur les articles

Numéros dans `inDebateNumeros` (`test/fixtures.dart`), hors de
`fixtureNumeros`.

| Scrutin | Séance | Intitulé (début) | Sort | Dans le bloc |
| --- | --- | --- | --- | --- |
| 8874 | 30949 | amendement de suppression de l'article 5 (PLF) | rejeté | non |
| 8875 | 30949 | amendement à l'article 5 (PLF) | adopté | non |
| 8876 | 30949 | l'article 5 (PLF) | adopté | article 5 adopté ; aussi sur le site (`../site/liste_scrutins.html`) |
| 8883 | 30950 | amendement de suppression de l'article 35 (examen prioritaire) | adopté | article 35 supprimé |
| 8885 | 30950 | amendement de suppression de l'article 36 | rejeté | non |
| 8887 | 30951 | amendement de suppression de l'article 37 | adopté | article 37 supprimé |
| 8888 | 30951 | l'article 38 (examen prioritaire) | adopté | article 38 adopté |
| 8889 | 30951 | amendement de suppression de l'article 39 | adopté | article 39 supprimé |
| 8891 | 30951 | amendement de suppression de l'article 40 | rejeté | non |
| 8892 | 30951 | l'article 40 (examen prioritaire) | rejeté | article 40 rejeté |
| 8895 | 30952 | motion de rejet préalable (PLFSS) | rejeté | non |
| 8896 | 30953 | amendement de suppression de l'article liminaire (PLFSS) | adopté | article liminaire supprimé |
| 8897 | 30953 | amendement de suppression de l'article premier (PLFSS) | adopté | article premier supprimé |
| 8905 | 30953 | l'article 4 (PLFSS) | adopté | article 4 adopté |
| 8931 | 30955 | amendement de suppression de l'article 5 (PLFSS) | adopté | article 5 supprimé |

## `dossiers/` : dossier du PLFSS 2027 (ticket #73)

`DLR5L17N54951.json`, extrait sans modification de
`Dossiers_Legislatifs.json.zip` téléchargé le 25/10/2026 (`Last-Modified:
Sun, 25 Oct 2026 11:16:27 GMT`) :
https://data.assemblee-nationale.fr/static/openData/repository/17/loi/dossiers_legislatifs/Dossiers_Legislatifs.json.zip

Ajouté aux dossiers de `../dossiers/` par `fixtureDossiersArchive(extra:
…)` dans les tests du résumé du texte en débat : son texte déposé est
`PRJLANR5L17B3211` (`../textes/`).
