# Fixtures : organes réels

Fichiers extraits sans modification de l'archive officielle
`AMO20_dep_sen_min_tous_mandats_et_organes.json.zip` (17e législature,
téléchargée le 17/10/2026) :
https://data.assemblee-nationale.fr/static/openData/repository/17/amo/deputes_senateurs_ministres_legislature/AMO20_dep_sen_min_tous_mandats_et_organes.json.zip

Source : Assemblée nationale, open data. Licence Ouverte / Open Licence (Etalab).

- Les 14 groupes politiques (`codeType` `GP`) de la législature, dont les
  groupes dissous ou renommés cités par d'anciens scrutins : `PO845520`
  (« À Droite », jusqu'au 11/09/2024) et `PO847173` (« UDR », jusqu'au
  04/09/2025, devenu `PO872880`).
- `PO59047` (Commission des affaires étrangères), qui n'est pas un groupe et
  doit être ignoré.

L'archive des seuls députés en exercice (AMO10) ne contient pas les groupes
dissous : c'est pourquoi le job lit AMO20.

Ajoutés pour le ticket #67 (arc dans l'ordre de l'hémicycle), même archive
téléchargée le 23/10/2026, dans `acteur/` : un député en exercice par groupe,
celui dont le siège (`mandature.placeHemicycle`) est le plus proche de la place
moyenne de son groupe, plus `PA840721` (UDR, ancien membre de `PO845520` et de
`PO847173`, groupes dissous).

| Acteur | Groupe | Siège |
| --- | --- | --- |
| PA842187 | LFI-NFP | 595 |
| PA796106 | GDR | 585 |
| PA795636 | EcoS | 514 |
| PA841681 | SOC | 462 |
| PA267042 | LIOT | 454 |
| PA795258 | Dem | 348 |
| PA840119 | NI | 322 |
| PA793924 | EPR | 309 |
| PA794838 | HOR | 242 |
| PA643089 | DR | 186 |
| PA330240 | UDR | 99 |
| PA840721 | UDR | 104 |
| PA795966 | RN | 76 |

Ajouté pour le ticket #71 (sièges du scrutin) : `hemicycle_acteurs.json`, les
654 députés de la 17e législature (574 en exercice, 80 partis), de la même
archive téléchargée le 07/11/2026 (`Last-Modified: Sat, 07 Nov 2026 01:00:35
GMT`), réduits aux champs que lit le job : `uid` (`#text`) et, parmi les
mandats de la 17e législature, ceux de type `ASSEMBLEE` (`dateDebut`,
`dateFin`, `mandature.datePriseFonction`, `mandature.placeHemicycle`,
`election.refCirconscription`) et `GP` (`dateDebut`, `dateFin`,
`organes.organeRef`). Avec les scrutins 8706 et 8610, ils redonnent les sièges
de `design/maquettes/data/seats.json`.

Cas utiles aux tests des sièges d'un jour passé :

| Acteur | Cas |
| --- | --- |
| PA841151 | quitte DR (`PO845425`) pour LIOT (`PO845485`) le 31/10/2026 ; absente au scrutin 8696 du 12/10 |
| PA794178 | démissionne le 08/07/2026, plus de siège dans l'archive |
| PA794182 | son suppléant, au siège 197 depuis le 09/07/2026 (même circonscription) |
| PA718884 | élue au Sénat le 30/09/2026, sans successeur dans l'archive |
