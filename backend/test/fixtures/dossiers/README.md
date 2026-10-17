# Fixtures : dossiers législatifs réels

Fichiers extraits sans modification de l'archive officielle
`Dossiers_Legislatifs.json.zip` (17e législature, `Last-Modified: Sat, 17 Oct
2026 13:16:27 GMT`) :
https://data.assemblee-nationale.fr/static/openData/repository/17/loi/dossiers_legislatifs/Dossiers_Legislatifs.json.zip

Source : Assemblée nationale, open data. Licence Ouverte / Open Licence (Etalab).

| Dossier | Scrutins | Particularité |
| --- | --- | --- |
| DLR5L17N50453 | 217 | 1re lecture (`AN1`) |
| DLR5L16N49258 | 504 | 2e lecture (`AN2`), dossier ouvert sous la 16e législature |
| DLR5L17N50588 | 519 | PLFSS 2025, cité par la motion de censure après 49.3 |
| DLR5L17N50975 | 519 | engagement de responsabilité (`AN21`) |
| DLR5L17N51279 | 1018 | résolution, lecture unique (`ANLUNI`) |
| DLR5L17N50169 | 1194 | décision sans `voteRef` (rattachement par l'intitulé) |
| DLR5L17N51002 | 2278 | CMP |
| DLR5L16N47697 | 2873 | motion de rejet préalable |
| DLR5L17N52428 | 4241 | PLF 2026 (première partie rejetée) |
| DLR5L17N52922 | 4696, 4758 | nouvelle lecture, lecture définitive |
| DLR5L17N53822 | 5731 | motion de censure 49.2 (`AN21`) |
| DLR5L17N52635 | 6346 | rattaché par `dossierRef` |
| DLR5L16N47722 | 289 | titre du dossier différent du texte voté |

`document/PIONANR5L17BTA0007.json` : texte adopté dont le titre rattache le
scrutin 289 au dossier DLR5L16N47722.

Ajoutés pour le ticket #8 (textes adoptés à main levée), même archive
téléchargée le 17/10/2026 (`Last-Modified: Sat, 17 Oct 2026 16:16:30 GMT`) :

| Dossier | Acte de décision | Particularité |
| --- | --- | --- |
| DLR5L17N54379 | L17-VD234087DEC (2026-10-07) | convention adoptée à main levée ; intitulé tiré du texte adopté `document/PRJLANR5L17BTA0347.json` |
| DLR5L17N53201 | L17-VD230548DEC (2026-02-16) | résolution adoptée à main levée, sans document : intitulé du dossier |
| DLR5L16N49852 | L17-VD224512DEC (2025-03-13) | main levée après des scrutins publics sur des articles (1011) |
| DLR5L16N47676 | L17-VD226757DEC (2025-06-23) | aucun `voteRef`, mais scrutin public sur l'article unique (2633) : pas de main levée |
| DLR5L17N52002 | L17-VD227011DEC (2025-07-02) | aucun `voteRef`, scrutin public 2900 non rattaché : doublon écarté par l'intitulé |

Cas déjà couverts par les dossiers précédents : décision sans `voteRef`
rattachée par l'intitulé (DLR5L17N50169, scrutin 1194) ou par `dossierRef`
(DLR5L17N52635, scrutin 6346), décision `CMP-DEBATS-DEC` du Sénat
(DLR5L16N47722), adoption ou rejet sans vote après un 49.3 (DLR5L17N50588,
DLR5L17N52428), rejets (DLR5L17N50453, DLR5L16N47697).

Ajouté pour le ticket #22 (article unique), même archive, dans
`article_unique/` (hors de l'archive de fixtures commune, ajouté par
`test/article_unique_test.dart`) :

| Dossier | Scrutins | Particularité |
| --- | --- | --- |
| DLR5L17N52700 | 7349 | résolution (art. 34-1) ; l'acte de décision cite le scrutin sur l'article unique |
