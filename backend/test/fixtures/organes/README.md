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
