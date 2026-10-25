---
version: alpha
name: Le Perchoir
description: Le système visuel de Le Perchoir, l'app et les widgets des décisions de l'Assemblée nationale. Inspiré de l'analyse du langage de Wired (collection awesome-design-md, licence MIT) — un duo noir et blanc de magazine imprimé, serif d'affichage en graisse 400, serif pour le récit, sans pour la structure, angles droits et filets de 1 px — adapté à une app de données civiques : la seule couleur vient des données (couleurs officielles des groupes, couleurs du vote).
inspiration: "awesome-design-md/design-md/wired (MIT). Aucun nom, logo ni police propriétaire de la marque n'est repris."

colors:
  light:
    ground: "#FFFFFF"
    surface: "#F5F5F5"
    raised: "#EBEBEB"
    ink: "#000000"
    ink2: "#6B6B6B"
    body: "#1A1A1A"
    rule: "#E0E0E0"
  dark:
    ground: "#000000"
    surface: "#121212"
    raised: "#1F1F1F"
    ink: "#FFFFFF"
    ink2: "#9E9E9E"
    body: "#E6E6E6"
    rule: "#2A2A2A"
  result:
    adopte-light: "#1D6B54"
    rejete-light: "#B4472B"
    adopte-dark: "#4FB08F"
    rejete-dark: "#E07A58"
  vote:        # sièges colorés par le vote (widgets, hémicycle gris d'attente exclu)
    pour-light: "#1D6B54"
    contre-light: "#E0683A"
    abst-light: "#848B91"
    pour-dark: "#4FB08F"
    contre-dark: "#B5461F"
    abst-dark: "#9AA2AB"
  groups:      # couleurAssociee de l'archive AMO de l'Assemblée, 17e législature
    LFI-NFP: "#C00D0D"
    GDR: "#830E21"
    EcoS: "#77AA79"
    SOC: "#F5B4CE"
    LIOT: "#FFD96F"
    Dem: "#F07E26"
    EPR: "#7B4591"
    HOR: "#B5E2F9"
    DR: "#8CB0DC"
    NI: "#8D949A"
    UDR: "#3367A7"
    RN: "#313567"

typography:
  display-xl: { fontFamily: Newsreader, fontSize: 72px, fontWeight: 400, lineHeight: 1, letterSpacing: -0.02em }   # jour de la carte vote, chiffre du creux
  display-lg: { fontFamily: Newsreader, fontSize: 34px, fontWeight: 400, lineHeight: 1.08, letterSpacing: -0.02em } # titre de l'écran, « Adopté » du détail
  display-md: { fontFamily: Newsreader, fontSize: 32px, fontWeight: 400, lineHeight: 1.1, letterSpacing: -0.01em }  # titre de la décision
  display-sm: { fontFamily: Newsreader, fontSize: 26px, fontWeight: 400, lineHeight: 1.12 }                         # intertitres, titre de carte, résultat
  body-serif: { fontFamily: Newsreader, fontSize: 18px, fontWeight: 400, lineHeight: 1.5 }                          # explication, points, arguments
  body-strong: { fontFamily: Geist, fontSize: 17px, fontWeight: 600, lineHeight: 1.3 }                              # titre d'une rangée de liste
  body-sm: { fontFamily: Geist, fontSize: 15px, fontWeight: 400, lineHeight: 1.45 }
  meta: { fontFamily: Geist, fontSize: 13px, fontWeight: 400, lineHeight: 1.4 }                                     # date, intitulé, source
  figure: { fontFamily: Geist, fontSize: 26px, fontWeight: 600, fontFeature: tnum }                                 # 503 · 0 · 67
  button: { fontFamily: Geist, fontSize: 16px, fontWeight: 700, letterSpacing: 0.02em }

rounded:
  none: 0px      # tout : cartes, rangées, boutons, sélecteurs, tuiles
  full: 9999px   # points de pagination, symboles du vote
  system: os     # cadres imposés par le téléphone (widgets, notifications) : forme du système

spacing: { xs: 4px, sm: 8px, md: 12px, lg: 16px, xl: 20px, 2xl: 24px, 3xl: 32px, 4xl: 48px }

components:
  card:            { backgroundColor: "{colors.surface}", rounded: "{rounded.none}", padding: "{spacing.xl}" }
  folder-tab:      { backgroundColor: "{colors.surface}", typography: "{typography.meta}", note: "languette de chemise au-dessus de la carte" }
  list-row:        { backgroundColor: transparent, borderBottom: "1px {colors.rule}", typography: "{typography.body-strong}", padding: "{spacing.lg} 0" }
  button-primary:  { backgroundColor: "{colors.ink}", textColor: "{colors.ground}", typography: "{typography.button}", rounded: "{rounded.none}", height: 48px }
  segmented:       { border: "1px {colors.ink}", selected: "{colors.ink} plein, texte {colors.ground}", rounded: "{rounded.none}" }
  chip:            { border: "1px {colors.rule}", selected: "{colors.ink} plein", rounded: "{rounded.none}" }
  group-tile:      { backgroundColor: "{colors.surface}", height: 100px, selected: "bord intérieur 2px {colors.ink}", rounded: "{rounded.none}" }
  hemicycle:       { seats: 574, note: "couleur du groupe, forme du vote ; voir Hémicycle" }
---

## Vue d'ensemble

Le Perchoir est d'abord un widget : la dernière décision de l'Assemblée, lue d'un coup d'œil sur l'écran d'accueil du téléphone. L'app est ce qu'on ouvre en le touchant. Le système emprunte à un magazine imprimé sa retenue — fond blanc (noir la nuit), encre pleine, aucune couleur de marque, aucune ombre, aucun arrondi — pour laisser la parole aux données : l'hémicycle et ses 574 places, colorées par groupe.

**Principes**
- **La couleur appartient aux données.** Les seules couleurs sont celles des groupes (officielles, AMO) et du vote. L'interface est en noir, blanc et gris.
- **Serif pour le récit, sans pour la structure.** Newsreader porte les titres, le résultat et les textes à lire ; Geist porte les rangées, les dates, les chiffres, les boutons.
- **Affichage en graisse 400.** L'élégance vient du dessin de la lettre, pas du gras.
- **Angles droits.** Cartes, rangées, boutons, sélecteurs, tuiles : 0 px. Seuls les cadres imposés par le système (widgets, notifications) gardent leur forme.
- **Peu de mots.** Un écran dit une chose : le résultat, le titre, les chiffres. Les explications sont dans le détail.

## Couleurs

Jour : fond `#FFFFFF`, surface `#F5F5F5`, encre `#000000`, texte secondaire `#6B6B6B` (5:1 sur la surface), filet `#E0E0E0`. Nuit : l'inverse, fond `#000000`, surface `#121212`, encre `#FFFFFF`, secondaire `#9E9E9E`, filet `#2A2A2A`.

Résultat : « Adopté » vert, « Rejeté » rouge, toujours écrits en toutes lettres (le résultat ne se lit jamais qu'à la couleur).

Vote coloré (widgets, où un siège fait 2 px et la forme ne se lit plus) : pour foncé, contre clair de jour, l'inverse de nuit, abstention gris moyen. Les trois restent distincts en deutéranopie simulée et tiennent 3:1 contre la surface.

Groupes : couleurs officielles inchangées. De jour, celles sous 3:1 sur blanc (HOR, LIOT, SOC, DR, EcoS, Dem, NI) prennent un contour 35 % plus sombre. De nuit, toutes sont éclaircies de 30 % vers le blanc.

## Typographie

| Jeton | Police | Taille / graisse | Usage |
|---|---|---|---|
| display-xl | Newsreader | 72 / 400 | jour de la carte vote |
| display-lg | Newsreader | 34 / 400 | titre d'écran, « Adopté » du détail |
| display-md | Newsreader | 32 / 400 | titre de la décision |
| display-sm | Newsreader | 26 / 400 | intertitres, titre de carte, résultat |
| body-serif | Newsreader | 18 / 400, interligne 1,5 | explication, points, arguments |
| body-strong | Geist | 17 / 600 | titre d'une rangée |
| meta | Geist | 13 / 400 | date, intitulé, source |
| figure | Geist | 26 / 600, chiffres tabulaires | 503 · 0 · 67 |
| button | Geist | 16 / 700 | bouton principal |

## Hémicycle

- 574 places réelles (plan du site de l'Assemblée, `placeHemicycle` AMO, `numPlace` du vote nominatif). Dôme ouvert vers le bas, vu du perchoir : LFI-NFP à l'extrême gauche, RN à l'extrême droite.
- Couleur = groupe ; forme = vote : rond plein pour, anneau contre, petit point abstention, siège à 28 % absent ou non-votant.
- Le résultat s'écrit sous l'hémicycle, jamais dans le creux.
- Texte en débat : tous les sièges en gris, même taille — personne n'a encore voté.
- Accessibilité : libellé « Adopté, 503 pour, 0 contre, 67 abstentions » ; tuiles de groupe annoncées comme boutons (« RN, pour, montrer ses sièges »).

## Composants

- **Carte de l'accueil** : surface douce, angle droit, languette de chemise (date ou « Vote solennel »). La carte suivante dépasse de 28 px.
- **Rangée de liste** : sur le fond, filet de 1 px dessous ; jauge d'une couleur (part du camp gagnant), titre court, « Adopté » ou « Rejeté ».
- **Bouton principal** : rectangle noir (blanc la nuit), 48 px de haut.
- **Sélecteurs** (apparence, filtres) : rectangles ; le choix en encre pleine.
- **Tuile de groupe** : logo sur tuile claire (même la nuit), sigle ; choisie, bord intérieur de 2 px.

## À faire / à ne pas faire

**À faire** : laisser la couleur aux données ; écrire le résultat en toutes lettres ; Newsreader 400 pour tout ce qui se lit comme un titre ; filets et changements de surface pour séparer.

**À ne pas faire** : couleur de marque, dégradé, ombre, arrondi ; texte gris clair sur gris ; résultat porté par la seule couleur ; plus d'une phrase sur une carte.
