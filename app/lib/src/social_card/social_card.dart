import 'package:flutter/material.dart';
import 'package:vote_contract/vote_contract.dart';

import '../hemicycle/hemicycle_places.dart';
import '../hemicycle/hemicycle_seats.dart' show seatRadius;
import '../theme.dart';
import 'social_card_content.dart';

/// Taille de la carte, en pixels : portrait 4:5 des fils mobiles.
const socialCardSize = Size(1080, 1350);

const _pad = 72.0;
const _contentWidth = 1080 - 2 * _pad;
const _arcWidth = 840.0;

/// Tailles du titre, de la plus grande à la plus petite, et lignes permises
/// à chacune : 2 lignes de 84 à 60 px, puis 3 lignes de 60 à 48 px (un titre
/// de 3 lignes en grand écrase l'hémicycle). Jamais tronqué : s'il ne tient
/// pas, il est à écrire à la main.
final _titleSteps = [
  for (var size = 84.0; size >= 60; size -= 4) (size: size, lines: 2),
  for (var size = 60.0; size >= 48; size -= 4) (size: size, lines: 3),
];

const _c = HemicycleColors.dark;

// Palette vote de DESIGN.md, mode sombre.
const _votePour = Color(0xFF4FB08F);
const _voteContre = Color(0xFFB5461F);
const _voteAbstention = Color(0xFF9AA2AB);
const _seatOff = Color(0xFF3A3A3A);

/// Taille du titre [title] sur la carte ([_titleSteps]), ou `null` s'il ne
/// tient pas en 3 lignes à 48 px : titre à écrire. Les polices de la carte
/// doivent être chargées.
double? socialTitleSize(String title) {
  for (final step in _titleSteps) {
    final painter = TextPainter(
      text: TextSpan(text: title, style: _titleStyle(step.size)),
      textDirection: TextDirection.ltr,
      maxLines: step.lines,
    )..layout(maxWidth: _contentWidth);
    final fits = !painter.didExceedMaxLines;
    painter.dispose();
    if (fits) return step.size;
  }
  return null;
}

TextStyle _titleStyle(double size) => HemicycleText.serif(
  size: size,
  height: 1.1,
  letterSpacing: -0.01 * size,
).copyWith(color: _c.ink);

TextStyle _geist(
  double size, {
  FontWeight weight = FontWeight.w700,
  Color? color,
}) => TextStyle(
  fontFamily: geist,
  fontSize: size,
  fontWeight: weight,
  color: color ?? _c.ink,
  height: 1,
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// La carte réseau social d'une décision (#109), 1080 × 1350, fond noir :
/// languette, titre, hémicycle coloré par le vote, légende des groupes par
/// camp, bandeau du résultat, pied. [titleSize] vient de [socialTitleSize].
class SocialCard extends StatelessWidget {
  const SocialCard({
    super.key,
    required this.content,
    required this.title,
    required this.titleSize,
  });

  final SocialCardContent content;
  final String title;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    final resultColor = content.result == VoteResult.adopte
        ? _c.pour
        : _c.contre;
    return Material(
      color: _c.background,
      child: SizedBox.fromSize(
        size: socialCardSize,
        child: Padding(
          padding: const EdgeInsets.all(_pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                color: _c.surface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                child: Text(
                  content.tab,
                  maxLines: 1,
                  style: _geist(
                    26,
                    weight: FontWeight.w600,
                    color: _c.ink2,
                  ).copyWith(letterSpacing: 1.5),
                ),
              ),
              const SizedBox(height: 24),
              Text(title, style: _titleStyle(titleSize)),
              const SizedBox(height: 28),
              // L'hémicycle prend la place qui reste : il rétrécit sous un
              // titre de 3 lignes et une légende de 3 lignes, sans déborder.
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: CustomPaint(
                      size: Size(
                        _arcWidth,
                        _arcWidth * hemicyclePlan.height / hemicyclePlan.width,
                      ),
                      painter: VoteSeatsPainter(
                        content.seats,
                        censure: content.censure,
                      ),
                    ),
                  ),
                ),
              ),
              if (content.legend.isNotEmpty) ...[
                const SizedBox(height: 20),
                _Legend(content),
              ],
              if (content.turnout case final turnout?) ...[
                const SizedBox(height: 14),
                Text(
                  turnout,
                  style: _geist(28, weight: FontWeight.w500, color: _c.ink2),
                ),
              ],
              const SizedBox(height: 28),
              Container(
                width: double.infinity,
                color: resultColor,
                padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      content.result == VoteResult.adopte ? 'ADOPTÉ' : 'REJETÉ',
                      style: _geist(
                        120,
                        color: _c.background,
                      ).copyWith(letterSpacing: -3),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      content.figures,
                      style: _geist(54, color: _c.background),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: _c.rule)),
                ),
                padding: const EdgeInsets.only(top: 24),
                child: Row(
                  children: [
                    Text('Le Perchoir', style: _geist(30)),
                    const Spacer(),
                    Text(
                      'Source : Assemblée nationale',
                      style: _geist(
                        24,
                        weight: FontWeight.w400,
                        color: _c.ink2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Légende de l'hémicycle : pour chaque camp, une pastille de la couleur de
/// ses sièges, son nom et ses groupes. Un camp ne se coupe pas : s'il ne
/// tient pas à la suite du précédent, il passe à la ligne.
class _Legend extends StatelessWidget {
  const _Legend(this.content);

  final SocialCardContent content;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 36,
      runSpacing: 12,
      children: [
        for (final line in content.legend)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentWidth),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 12),
                  child: _dot(line.position),
                ),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: line.label),
                        if (line.groups.isNotEmpty)
                          TextSpan(
                            text: '\u00A0 ${line.groups}',
                            style: _geist(
                              28,
                              weight: FontWeight.w400,
                              color: _c.ink2,
                            ).copyWith(height: 1.25),
                          ),
                      ],
                    ),
                    style: _geist(
                      28,
                      weight: FontWeight.w600,
                    ).copyWith(height: 1.25),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Pastille d'un camp : la couleur de ses sièges ; un groupe partagé, à
  /// cheval sur plusieurs votes, n'a qu'un contour.
  Widget _dot(GroupPosition position) {
    final color = switch (position) {
      GroupPosition.pour => socialSeatColor(
        SeatVote.pour,
        censure: content.censure,
      ),
      GroupPosition.contre => _voteContre,
      GroupPosition.abstention => _voteAbstention,
      _ => null,
    };
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: color == null ? Border.all(color: _c.ink2, width: 3) : null,
      ),
    );
  }
}

/// Couleur d'un siège de la carte : la couleur dit le vote (la position dit
/// le groupe). Motion de censure : soutiens en encre neutre, jamais le vert
/// du « ça passe ». Absents et non-votants très atténués.
Color socialSeatColor(SeatVote vote, {required bool censure}) => switch (vote) {
  SeatVote.pour when censure => _c.ink,
  SeatVote.pour => _votePour,
  SeatVote.contre => _voteContre,
  SeatVote.abstention => _voteAbstention,
  SeatVote.nonVotant || SeatVote.absent => _seatOff.withValues(alpha: 0.6),
};

/// Sièges du scrutin à leur place réelle, en disques pleins colorés par
/// [socialSeatColor].
class VoteSeatsPainter extends CustomPainter {
  VoteSeatsPainter(this.seats, {required this.censure});

  final List<HemicycleSeat> seats;
  final bool censure;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / hemicyclePlan.width;
    canvas
      ..save()
      ..scale(unit)
      ..translate(-hemicyclePlan.left, -hemicyclePlan.top);
    final fill = Paint()..isAntiAlias = true;
    for (final seat in seats) {
      final center = hemicyclePlaces[seat.place];
      if (center == null) continue;
      canvas.drawCircle(
        center,
        seatRadius,
        fill..color = socialSeatColor(seat.vote, censure: censure),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(VoteSeatsPainter old) =>
      old.seats != seats || old.censure != censure;
}
