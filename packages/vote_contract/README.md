# vote_contract

Contrat de données partagé entre le job (`backend/`) et l'app (`app/`).

- `schemaVersion` : version du format JSON publié (actuellement 1).
- `indexPath` : chemin de l'index, `v1/latest.json`, relatif à l'URL publique.
- `DecisionIndex` / `DecisionSummary` : lecture et écriture du JSON.

Compatibilité : ajouter un champ optionnel garde la version ; tout changement
cassant incrémente `schemaVersion` et publie sous `v<N>/`, à côté de l'ancien
format tant que des versions de l'app le lisent. Une décision portant une valeur
d'énumération inconnue est ignorée par les lecteurs plus anciens.

Exemple de `v1/latest.json` :

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-10-17T10:17:00.000Z",
  "source": {
    "name": "Assemblée nationale — open data",
    "url": "https://data.assemblee-nationale.fr",
    "license": "Licence Ouverte / Open Licence (Etalab)",
    "licenseUrl": "https://www.etalab.gouv.fr/licence-ouverte-open-licence/"
  },
  "decisions": [
    {
      "id": "VTANR5L17V8706",
      "numero": 8706,
      "type": "ensemble",
      "status": "confirmee",
      "result": "adopte",
      "date": "2026-10-13",
      "officialTitle": "la proposition de loi organique visant à …",
      "sourceUrl": "https://www.assemblee-nationale.fr/dyn/17/scrutins/8706"
    }
  ]
}
```

Valeurs :

- `type` : `ensemble` (vote sur un projet ou une proposition de loi),
  `motion_de_censure`, `declaration_gouvernement` (art. 50-1 ou déclaration de
  politique générale), `rejet_prealable` (motion de rejet préalable adoptée),
  `premiere_partie_budget` (rejet de la première partie d'une loi de finances,
  le texte tombe), `resolution` (proposition de résolution), `autre` (scrutin
  solennel dont l'intitulé n'est pas reconnu) ;
- `result` : `adopte`, `rejete` — l'issue à afficher pour le texte : pour
  `rejet_prealable`, la motion est adoptée donc `result` vaut `rejete` ;
- `status` : `provisoire`, `confirmee`.
