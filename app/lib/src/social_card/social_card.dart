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

/// Tailles du titre, de la plus grande à la plus petite : le titre n'est
/// jamais tronqué ; s'il ne tient pas en [_titleMaxLines] lignes à la plus
/// petite, il est à écrire à la main.
const _titleMaxSize = 84.0;
const _titleMinSize = 48.0;
const _titleMaxLines = 3;

const _c = HemicycleColors.dark;

// Palette vote de DESIGN.md, mode sombre.
const _votePour = Color(0xFF4FB08F);
const _voteContre = Color(0xFFB5461F);
const _voteAbstention = Color(0xFF9AA2AB);
const _seatOff = Color(0xFF3A3A3A);

/// Taille du titre [title] sur la carte, de 84 à 48 px, ou `null` s'il ne
/// tient pas en 3 lignes : titre à écrire. Les polices de la carte doivent
/// être chargées.
double? socialTitleSize(String title) {
  for (var size = _titleMaxSize; size >= _titleMinSize; size -= 4) {
    final painter = TextPainter(
      text: TextSpan(text: title, style: _titleStyle(size)),
      textDirection: TextDirection.ltr,
      maxLines: _titleMaxLines,
    )..layout(maxWidth: _contentWidth);
    final fits = !painter.didExceedMaxLines;
    painter.dispose();
    if (fits) return size;
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
/// languette, titre, hémicycle coloré par le vote, bandeau du résultat,
/// pied. [titleSize] vient de [socialTitleSize].
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
              const Spacer(),
              Center(
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
              if (content.turnout case final turnout?) ...[
                const SizedBox(height: 16),
                Text(
                  turnout,
                  style: _geist(30, weight: FontWeight.w500, color: _c.ink2),
                ),
              ],
              const Spacer(),
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
