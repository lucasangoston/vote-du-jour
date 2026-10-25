# Phase 2 — tâches relevées pendant les maquettes (25/10)

- Backend : titre court par décision et par texte en débat (≤ 35 caractères, pour les widgets et la liste).
- Backend : résumé IA d'un texte dès qu'il passe en séance (dossier législatif, exposé des motifs), mêmes champs
  qu'une décision (explication, points) ; réutilisé au vote final. Un appel par texte, dans le plafond par passage.
- Backend/contrat : sièges du scrutin (place, groupe, vote) et couleurs officielles des groupes (AMO couleurAssociee).
- Notification « En débat aujourd'hui » quand un texte passe en séance ; elle ouvre l'écran « En débat ».
- Accueil : la carte « En débat » sort de la pile.
- Widgets : hémicycle coloré par le vote (pas par groupe), petit / moyen / grand + petit « prochain vote ».
- Liste : jauge d'une couleur (part du camp gagnant), plus de chiffres à côté du résultat.

## Revue UI/UX (skill ui-ux-pro-max, 25/10)

- Vote coloré (widgets, mode vote) : pour foncé / contre clair de jour (#1D6B54 / #E0683A), l'inverse de nuit
  (#4FB08F / #B5461F), abstention gris moyen (#8D949A / #9AA2AB) : distincts en deutéranopie simulée, ≥ 3:1 contre la surface.
- Couleurs de groupe sous 3:1 sur blanc (HOR, LIOT, SOC, DR, EcoS, Dem, NI) : contour 35 % plus sombre, de jour seulement.
- Absents et non-votants : 28 % d'opacité (20 % disparaissait de jour).
- Hémicycle : libellé lu par le lecteur d'écran avec résultat et totaux ; tuiles de groupe annoncées comme boutons
  (« RN, pour, montrer ses sièges ») ; tuile choisie : bord plein en plus du fond.
- Accueil : la carte suivante dépasse de 28 px ; la carte suit son contenu, centrée entre le titre et le bouton.
- Widgets : nombre de lignes maximal et léger rétrécissement du texte pour les grandes tailles de texte du téléphone.
