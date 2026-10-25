import 'package:flutter/material.dart';
import 'package:vote_contract/vote_contract.dart';

import '../theme.dart';
import 'hemicycle_places.dart';

/// Forme d'un siège : celle du vote (#74), comme les symboles de la légende
/// ([VoteGlyph]) : rond plein pour, anneau contre, petit point abstention.
/// Un absent ou un non-votant garde le rond plein, estompé.
enum SeatShape { disc, ring, dot }

/// Un siège à dessiner : centre dans le plan ([hemicyclePlan]), forme,
/// couleur du groupe, contour éventuel et opacité.
@immutable
class SeatMark {
  const SeatMark({
    required this.place,
    required this.group,
    required this.center,
    required this.shape,
    required this.color,
    required this.opacity,
    this.outline,
  });

  final int place;

  /// Référence du groupe (organe), pour allumer ses sièges.
  final String group;

  final Offset center;
  final SeatShape shape;
  final Color color;

  /// Contour plus sombre des couleurs claires, de jour seulement.
  final Color? outline;

  final double opacity;

  @override
  bool operator ==(Object other) =>
      other is SeatMark &&
      other.place == place &&
      other.group == group &&
      other.center == center &&
      other.shape == shape &&
      other.color == color &&
      other.outline == outline &&
      other.opacity == opacity;

  @override
  int get hashCode =>
      Object.hash(place, group, center, shape, color, outline, opacity);
}

/// Rayon d'un siège plein et épaisseur de l'anneau, en unités du plan (ceux
/// des maquettes).
const seatRadius = 2.15;
const seatRingWidth = 1.05;

/// Épaisseur du contour des couleurs claires, en unités du plan.
const seatOutlineWidth = 0.55;

/// Opacité d'un absent ou d'un non-votant : 28 % (20 % disparaissait de
/// jour, revue UI/UX).
const seatOffOpacity = 0.28;

/// Opacité des sièges des autres groupes quand un groupe est allumé.
const seatDimmedOpacity = 0.16;

/// Couleur d'un groupe sans couleur officielle publiée : le gris des
/// non-inscrits.
const fallbackGroupColor = Color(0xFF8D949A);

/// Vrai si toutes les places de [seats] sont connues du plan : sinon
/// l'hémicycle aurait des trous, le détail garde l'arc.
bool canDrawSeats(List<HemicycleSeat>? seats) =>
    seats != null &&
    seats.isNotEmpty &&
    seats.every((s) => hemicyclePlaces.containsKey(s.place));

/// Couleur officielle `#RRGGBB` d'un groupe, ou [fallbackGroupColor].
Color groupColor(String? hex) {
  final value = hex == null || hex.length != 7
      ? null
      : int.tryParse(hex.substring(1), radix: 16);
  return value == null ? fallbackGroupColor : Color(0xFF000000 | value);
}

/// Couleur d'un siège du groupe de couleur [official] : de nuit, éclaircie
/// de 30 % vers le blanc (RN, GDR, UDR disparaissaient sur la surface
/// sombre), teinte inchangée.
Color seatColor(Color official, Brightness brightness) =>
    brightness == Brightness.dark
    ? Color.lerp(official, const Color(0xFFFFFFFF), 0.3)!
    : official;

/// Contour d'un siège de jour : une couleur officielle sous 3:1 contre le
/// blanc (HOR, LIOT, SOC, DR, EcoS, Dem, NI) prend un contour 35 % plus
/// sombre ; `null` de nuit ou pour une couleur assez contrastée.
Color? seatOutline(Color official, Brightness brightness) {
  if (brightness == Brightness.dark) return null;
  final contrast = 1.05 / (official.computeLuminance() + 0.05);
  return contrast < 3
      ? Color.lerp(official, const Color(0xFF000000), 0.35)
      : null;
}

/// Sièges à dessiner, dans l'ordre des places. [lit] : référence du groupe
/// allumé (tuile touchée) ; les sièges des autres groupes s'estompent.
List<SeatMark> seatMarks({
  required List<HemicycleSeat> seats,
  required List<GroupVoteDetail> groups,
  required Brightness brightness,
  String? lit,
}) {
  final colors = {for (final g in groups) g.organeRef: groupColor(g.color)};
  return [
    for (final seat in seats)
      if (hemicyclePlaces[seat.place] case final center?)
        _seatMark(
          seat,
          center,
          colors[seat.group] ?? fallbackGroupColor,
          brightness,
          lit,
        ),
  ];
}

SeatMark _seatMark(
  HemicycleSeat seat,
  Offset center,
  Color official,
  Brightness brightness,
  String? lit,
) {
  final shape = switch (seat.vote) {
    SeatVote.contre => SeatShape.ring,
    SeatVote.abstention => SeatShape.dot,
    SeatVote.pour || SeatVote.nonVotant || SeatVote.absent => SeatShape.disc,
  };
  final off = seat.vote == SeatVote.absent || seat.vote == SeatVote.nonVotant;
  return SeatMark(
    place: seat.place,
    group: seat.group,
    center: center,
    shape: shape,
    color: seatColor(official, brightness),
    // L'anneau est déjà un trait : pas de contour en plus.
    outline: shape == SeatShape.ring ? null : seatOutline(official, brightness),
    opacity: lit != null && seat.group != lit
        ? seatDimmedOpacity
        : off
        ? seatOffOpacity
        : 1,
  );
}

/// Description de l'hémicycle pour les lecteurs d'écran : « Adopté, 503
/// pour, 0 contre, 67 abstentions ».
String hemicycleSeatsLabel(VoteResult result, VoteTally count) {
  final word = switch (result) {
    VoteResult.adopte => 'Adopté',
    VoteResult.rejete => 'Rejeté',
  };
  return '$word, ${count.pour} pour, ${count.contre} contre, '
      '${count.abstentions} abstentions';
}

/// Sièges estompés, dits en clair sous l'hémicycle : « 236 absents ». Ils
/// comptent aussi les non-votants (président de séance…), un ou deux : « n'ont
/// pas voté » se confondait avec l'abstention, qui est un vote. `null` si
/// tout le monde a voté.
String? noVoteNote(List<HemicycleSeat> seats) {
  final n = seats
      .where((s) => s.vote == SeatVote.absent || s.vote == SeatVote.nonVotant)
      .length;
  if (n == 0) return null;
  return n == 1 ? '1 absent' : '$n absents';
}

/// La mention [noVoteNote] en texte secondaire, ou rien.
class NoVoteNote extends StatelessWidget {
  const NoVoteNote(this.seats, {super.key});

  final List<HemicycleSeat> seats;

  @override
  Widget build(BuildContext context) {
    final note = noVoteNote(seats);
    if (note == null) return const SizedBox.shrink();
    return Text(
      note,
      style: HemicycleText.meta.copyWith(color: context.colors.ink2),
    );
  }
}

/// L'hémicycle aux places réelles (#74) : chaque député à sa place, couleur
/// officielle de son groupe, forme selon son vote. Dôme ouvert vers le bas,
/// LFI-NFP à l'extrême gauche, RN à droite. La hauteur suit la largeur
/// ([aspect]).
class HemicycleSeats extends StatelessWidget {
  const HemicycleSeats({
    super.key,
    required this.seats,
    required this.groups,
    required this.result,
    required this.count,
    required this.width,
    this.lit,
  });

  final List<HemicycleSeat> seats;
  final List<GroupVoteDetail> groups;
  final VoteResult result;
  final VoteTally count;
  final double width;

  /// Référence du groupe allumé, s'il y en a un.
  final String? lit;

  /// Rapport hauteur / largeur du plan.
  static final aspect = hemicyclePlan.height / hemicyclePlan.width;

  @override
  Widget build(BuildContext context) {
    final marks = seatMarks(
      seats: seats,
      groups: groups,
      brightness: Theme.of(context).brightness,
      lit: lit,
    );
    return Semantics(
      container: true,
      image: true,
      label: hemicycleSeatsLabel(result, count),
      child: CustomPaint(
        size: Size(width, width * aspect),
        painter: HemicycleSeatsPainter(marks),
      ),
    );
  }
}

/// Dessine [marks] dans le plan ([hemicyclePlan]) mis à l'échelle de la
/// largeur.
class HemicycleSeatsPainter extends CustomPainter {
  HemicycleSeatsPainter(this.marks);

  final List<SeatMark> marks;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / hemicyclePlan.width;
    canvas
      ..save()
      ..scale(unit)
      ..translate(-hemicyclePlan.left, -hemicyclePlan.top);
    final fill = Paint()..isAntiAlias = true;
    final stroke = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke;
    for (final m in marks) {
      switch (m.shape) {
        case SeatShape.ring:
          // Trait centré sur le cercle : l'anneau garde le diamètre d'un
          // siège plein.
          canvas.drawCircle(
            m.center,
            seatRadius - seatRingWidth / 2,
            stroke
              ..strokeWidth = seatRingWidth
              ..color = m.color.withValues(alpha: m.opacity),
          );
        case SeatShape.disc || SeatShape.dot:
          final r = m.shape == SeatShape.dot ? seatRadius / 2 : seatRadius;
          canvas.drawCircle(
            m.center,
            r,
            fill..color = m.color.withValues(alpha: m.opacity),
          );
          if (m.outline case final outline?) {
            canvas.drawCircle(
              m.center,
              r,
              stroke
                ..strokeWidth = seatOutlineWidth
                ..color = outline.withValues(alpha: m.opacity),
            );
          }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(HemicycleSeatsPainter old) =>
      old.marks.length != marks.length ||
      [
        for (var i = 0; i < marks.length; i++) old.marks[i] == marks[i],
      ].contains(false);
}

/// Part de l'encre dans le gris des sièges d'attente, mêlée à la surface
/// (`.seat.s-wait` des maquettes).
const waitingSeatInk = 0.22;

/// Sièges de l'hémicycle d'attente (#77) : toutes les places du plan, même
/// taille, même gris [color] ; personne n'a encore voté.
List<SeatMark> waitingSeatMarks(Color color) => [
  for (final MapEntry(key: place, value: center) in hemicyclePlaces.entries)
    SeatMark(
      place: place,
      group: '',
      center: center,
      shape: SeatShape.disc,
      color: color,
      opacity: 1,
    ),
];

/// L'hémicycle d'un texte en débat (#77) : toutes les places en gris, sans
/// groupe ni vote. Décoratif : le texte de la carte dit déjà « En débat ».
class WaitingHemicycle extends StatelessWidget {
  const WaitingHemicycle({super.key, required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(width, width * HemicycleSeats.aspect),
        painter: HemicycleSeatsPainter(
          waitingSeatMarks(
            Color.lerp(colors.surface, colors.ink, waitingSeatInk)!,
          ),
        ),
      ),
    );
  }
}
