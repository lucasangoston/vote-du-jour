import 'package:vote_contract/vote_contract.dart';

import 'group_directory.dart';
import 'scrutin.dart';

/// Place de repli des groupes de la 17e législature dans l'hémicycle (#67),
/// par sigle, pour un groupe dont l'annuaire ne donne pas la place (archive
/// des acteurs sans siège, annuaire en cache ancien).
///
/// Valeurs relevées le 23/10/2026 : place moyenne des députés de chaque
/// groupe (`placeHemicycle` de l'archive AMO20), dans la même échelle que
/// [PoliticalGroup.place]. De gauche à droite : LFI-NFP, GDR, EcoS, SOC,
/// LIOT, Dem, EPR, HOR, DR, UDR, RN, conforme au plan de l'hémicycle du site
/// de l'Assemblée (sièges numérotés de la droite vers la gauche).
///
/// Les non-inscrits n'y figurent pas : sans place connue, ils vont à droite,
/// comme un groupe inconnu.
const fallbackGroupPlaces = <String, double>{
  'LFI-NFP': 594.7,
  'GDR': 584.8,
  'EcoS': 514.3,
  'SOC': 461.7,
  'LIOT': 446.3,
  'Dem': 348.1,
  'EPR': 309.3,
  'HOR': 242.3,
  'DR': 185.8,
  'UDR': 100.0,
  'RN': 75.9,
};

/// Place d'un groupe sans place connue ni sigle de [fallbackGroupPlaces]
/// (non-inscrits, groupe inconnu) : à droite de tous les autres.
const _rightmost = 0.0;

/// Place du groupe [organeRef] dans l'hémicycle : celle de l'annuaire
/// [groups], sinon celle de son sigle dans [fallbackGroupPlaces], sinon à
/// droite. Plus elle est grande, plus le groupe siège à gauche.
double groupPlace(String organeRef, GroupDirectory? groups) {
  final group = groups?[organeRef];
  return group?.place ?? fallbackGroupPlaces[group?.abbreviation] ?? _rightmost;
}

/// Arc du vote dans l'ordre de l'hémicycle (#67) : les groupes de gauche à
/// droite ([groupPlace], à place égale par référence d'organe), chacun
/// découpé selon les votes de ses membres. Les non-votants n'y figurent pas.
/// Les tronçons voisins de même sens sont fusionnés.
///
/// Dans un groupe, l'abstention, neutre, reste entre pour et contre ; le
/// sens de lecture (pour, abstention, contre, ou l'inverse) place les voix
/// du groupe à côté des voisins qui votent comme elles : de même couleur que
/// la fin de l'arc à sa gauche, et que le vote majoritaire du groupe suivant
/// à sa droite. L'arc a ainsi le moins de morceaux possible et l'abstention
/// d'un groupe placé à une extrémité reste à cette extrémité (8706 : LFI-NFP
/// s'abstient, ses 4 voix pour rejoignent celles des autres groupes). À
/// égalité, pour, abstention, contre : l'ordre de l'arc par sens.
///
/// `null` sans vote par groupe (scrutin lu sur le site) ou sans voix
/// exprimée : l'arc se dessine alors par sens.
List<HemicycleSegment>? hemicycleArc(
  List<GroupVote> votes,
  GroupDirectory? groups,
) {
  final ordered =
      [
        for (final g in votes)
          if (g.decompte.pour + g.decompte.abstentions + g.decompte.contre > 0)
            g,
      ]..sort((a, b) {
        final byPlace = groupPlace(
          b.organeRef,
          groups,
        ).compareTo(groupPlace(a.organeRef, groups));
        return byPlace != 0 ? byPlace : a.organeRef.compareTo(b.organeRef);
      });
  final segments = <HemicycleSegment>[];
  for (var i = 0; i < ordered.length; i++) {
    final parts = _parts(ordered[i].decompte);
    final reversed = parts.reversed.toList();
    final left = segments.lastOrNull?.position;
    final right = i + 1 < ordered.length
        ? _majority(ordered[i + 1].decompte)
        : null;
    int score(List<HemicycleSegment> order) =>
        (order.first.position == left ? 1 : 0) +
        (order.last.position == right ? 1 : 0);
    segments.addAll(score(reversed) > score(parts) ? reversed : parts);
  }
  final arc = HemicycleSegment.merge(segments);
  return arc.isEmpty ? null : arc;
}

/// Voix exprimées d'un groupe, non nulles : pour, abstention, contre.
List<HemicycleSegment> _parts(Decompte d) => [
  for (final s in [
    HemicycleSegment(ArcPosition.pour, d.pour),
    HemicycleSegment(ArcPosition.abstention, d.abstentions),
    HemicycleSegment(ArcPosition.contre, d.contre),
  ])
    if (s.n > 0) s,
];

/// Sens qui a recueilli le plus de voix dans le groupe (à égalité, le premier
/// de pour, abstention, contre).
ArcPosition _majority(Decompte d) =>
    _parts(d).reduce((best, s) => s.n > best.n ? s : best).position;

/// Arcs des [scrutins] qui ont un vote par groupe, par identifiant de
/// scrutin.
Map<String, List<HemicycleSegment>> hemicycleArcs(
  Iterable<Scrutin> scrutins,
  GroupDirectory? groups,
) => {for (final s in scrutins) s.uid: ?hemicycleArc(s.groupVotes, groups)};
