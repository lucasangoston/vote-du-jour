# Maquettes de la refonte (octobre 2026)

Maquettes HTML statiques, générées à partir de données réelles de l'Assemblée. Elles servent de référence à la phase 2.

- `screens/index.html` : la planche, tous les écrans côte à côte, jour et nuit.
- `screens/*-clair.html`, `*-sombre.html` : un écran par fichier (widgets, notification, en débat, accueil, liste, détail adopté 8706, détail rejeté 8610, à propos).
- `shots/` : captures à 390 px.
- `../../DESIGN.md` : le système visuel (inspiré de Wired, collection awesome-design-md).
- `screens/palettes.html` : comparaison des palettes du vote (la palette actuelle est retenue).
- `PHASE2.md` : les changements à porter dans l'app, le backend et les widgets.
- `data/an-seats.json` : centre de chacune des places de l'hémicycle, relevé sur le plan SVG du site de l'Assemblée (`an-hemicycle.svg`).
- `data/seats.json` : place, groupe et vote de chaque député pour 8706 et 8610 (archive AMO `placeHemicycle`, Scrutins.json `numPlace`), produit par `prep_seats.py`.

Régénérer : `node build.mjs`, puis `node shots.mjs` (Chrome requis).
