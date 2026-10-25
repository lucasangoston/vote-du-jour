// Génère la géométrie de l'hémicycle des widgets natifs (#78) à partir du relevé des places
// de la maquette (design/maquettes/data/an-seats.json, centre de chaque place du plan SVG du
// site de l'Assemblée) :
//   - ios/DecisionWidget/HemicycleGeometry.swift
//   - android/app/src/main/kotlin/com/lucasangoston/votedujour/widget/HemicycleGeometry.kt
//   - android/app/src/main/res/drawable/decision_widget_preview_hemicycle.xml (aperçu du
//     sélecteur de widgets, sièges du scrutin 8706 de design/maquettes/data/seats.json)
//
// Depuis app/ : node tool/widget_hemicycle.mjs
// Les fichiers générés sont versionnés ; ne pas les modifier à la main.
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const app = join(dirname(fileURLToPath(import.meta.url)), '..');
const data = join(app, '..', 'design', 'maquettes', 'data');
const read = (f) => JSON.parse(readFileSync(join(data, f), 'utf8'));

// Cadre et rayon d'un siège de l'hémicycle sans étiquettes de la maquette (build.mjs,
// realHemi : viewBox « 4 3 229 128 », r = 2.15).
const VIEW = { x: 4, y: 3, width: 229, height: 128 };
const SEAT_RADIUS = 2.15;

const seats = read('an-seats.json');
const places = Object.keys(seats).map(Number).sort((a, b) => a - b);
for (const p of places) {
  const { x, y } = seats[p];
  if (x < VIEW.x || x > VIEW.x + VIEW.width || y < VIEW.y || y > VIEW.y + VIEW.height) {
    throw new Error(`place ${p} hors du cadre : ${x}, ${y}`);
  }
}
// Exemple de la galerie et des aperçus : sièges du scrutin 8706 (adopté, 503 pour, 0 contre,
// 67 abstentions), au format de l'instantané (lettre du vote de la place i + 1, « - » sans député).
const sample = read('seats.json')['8706'].seats;
const LETTER = { pour: 'p', contre: 'c', abst: 'a', nv: 'n', absent: 'x' };
const byPlace = new Map(sample.map((s) => [s.place, LETTER[s.v]]));
const lastPlace = Math.max(...byPlace.keys());
const sampleVotes = Array.from({ length: lastPlace }, (_, i) => byPlace.get(i + 1) ?? '-').join('');
const chunks = (text, size) => text.match(new RegExp(`.{1,${size}}`, 'g'));
const num = (v) => String(Number(v.toFixed(2)));
const rows = (values, perLine, indent) => {
  const lines = [];
  for (let i = 0; i < values.length; i += perLine) lines.push(indent + values.slice(i, i + perLine).join(', ') + ',');
  return lines.join('\n');
};
const header = (c) => `${c} Généré par app/tool/widget_hemicycle.mjs depuis design/maquettes/data/an-seats.json :\n${c} ne pas modifier à la main.`;

const swift = `${header('//')}

/// Centre de chacune des ${places.length} places de l'hémicycle, relevé sur le plan SVG du site de
/// l'Assemblée (repère de la maquette : cadre \`viewBox\`, ordonnées vers le bas). Les places
/// vont de la droite (1) vers la gauche ; certains numéros n'existent pas.
enum HemicycleGeometry {
  /// Cadre du dessin dans le repère des places.
  static let viewBox = (x: ${VIEW.x}.0, y: ${VIEW.y}.0, width: ${VIEW.width}.0, height: ${VIEW.height}.0)

  /// Rayon d'un siège dans ce repère.
  static let seatRadius = ${SEAT_RADIUS}

  /// Numéros des places, croissants ; \`xs\` et \`ys\` donnent leur centre, au même rang.
  static let places: [Int] = [
${rows(places.map(String), 16, '    ')}
  ]

  static let xs: [Double] = [
${rows(places.map((p) => num(seats[p].x)), 12, '    ')}
  ]

  static let ys: [Double] = [
${rows(places.map((p) => num(seats[p].y)), 12, '    ')}
  ]

  /// Sièges du scrutin 8706 (adopté, 503 pour, 0 contre, 67 abstentions), au format de
  /// l'instantané : exemple de la galerie et des aperçus.
  static let sampleVotes = [
${chunks(sampleVotes, 80).map((c) => `    "${c}",`).join('\n')}
  ].joined()
}
`;

const kotlin = `${header('//')}

package com.lucasangoston.votedujour.widget

/**
 * Centre de chacune des ${places.length} places de l'hémicycle, relevé sur le plan SVG du site de
 * l'Assemblée (repère de la maquette : cadre [VIEW_X], [VIEW_Y], [VIEW_WIDTH], [VIEW_HEIGHT],
 * ordonnées vers le bas). Les places vont de la droite (1) vers la gauche ; certains numéros
 * n'existent pas.
 */
object HemicycleGeometry {
  const val VIEW_X = ${VIEW.x}f
  const val VIEW_Y = ${VIEW.y}f
  const val VIEW_WIDTH = ${VIEW.width}f
  const val VIEW_HEIGHT = ${VIEW.height}f

  /** Rayon d'un siège dans ce repère. */
  const val SEAT_RADIUS = ${SEAT_RADIUS}f

  /** Numéros des places, croissants ; [XS] et [YS] donnent leur centre, au même rang. */
  val PLACES =
      intArrayOf(
${rows(places.map(String), 16, '          ')}
      )

  val XS =
      floatArrayOf(
${rows(places.map((p) => num(seats[p].x) + 'f'), 10, '          ')}
      )

  val YS =
      floatArrayOf(
${rows(places.map((p) => num(seats[p].y) + 'f'), 10, '          ')}
      )

  /**
   * Sièges du scrutin 8706 (adopté, 503 pour, 0 contre, 67 abstentions), au format de
   * l'instantané : exemple des aperçus.
   */
  val SAMPLE_VOTES =
      listOf(
${chunks(sampleVotes, 80).map((c) => `              "${c}",`).join('\n')}
          )
          .joinToString("")
}
`;

// Aperçu Android : sièges de 8706, couleurs du vote.
const circle = (x, y, r) => `M${num(x - r)},${num(y)}a${r},${r} 0,1 0,${num(2 * r)},0a${r},${r} 0,1 0,${num(-2 * r)},0`;
const kinds = [
  ['off', (v) => v === 'nv' || v === 'absent', SEAT_RADIUS, '@color/decision_widget_seat_off', ' android:fillAlpha="0.28"'],
  ['pour', (v) => v === 'pour', SEAT_RADIUS, '@color/decision_widget_vote_pour', ''],
  ['contre', (v) => v === 'contre', SEAT_RADIUS, '@color/decision_widget_vote_contre', ''],
  ['abstention', (v) => v === 'abst', SEAT_RADIUS / 2, '@color/decision_widget_vote_abstention', ''],
];
const paths = kinds
  .map(([name, test, r, color, extra]) => {
    const d = sample.filter((s) => test(s.v)).map((s) => circle(seats[s.place].x, seats[s.place].y, r)).join('');
    return d ? `    <!-- ${name} -->\n    <path android:fillColor="${color}"${extra} android:pathData="${d}" />` : '';
  })
  .filter(Boolean)
  .join('\n');
const preview = `<?xml version="1.0" encoding="utf-8"?>
<!-- Généré par app/tool/widget_hemicycle.mjs : ne pas modifier à la main.
     Hémicycle de l'aperçu des widgets (sélecteur), sièges du scrutin 8706 colorés par le vote. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="${VIEW.width}dp"
    android:height="${VIEW.height}dp"
    android:viewportWidth="${VIEW.width}"
    android:viewportHeight="${VIEW.height}">
  <group android:translateX="${-VIEW.x}" android:translateY="${-VIEW.y}">
${paths}
  </group>
</vector>
`;

writeFileSync(join(app, 'ios', 'DecisionWidget', 'HemicycleGeometry.swift'), swift);
writeFileSync(join(app, 'android', 'app', 'src', 'main', 'kotlin', 'com', 'lucasangoston', 'votedujour', 'widget', 'HemicycleGeometry.kt'), kotlin);
writeFileSync(join(app, 'android', 'app', 'src', 'main', 'res', 'drawable', 'decision_widget_preview_hemicycle.xml'), preview);
console.log(`${places.length} places, aperçu de ${sample.length} sièges`);
