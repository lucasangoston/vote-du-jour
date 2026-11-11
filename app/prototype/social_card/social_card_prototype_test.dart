// PROTOTYPE jetable (branche content-factory) : cartes réseau social de
// Le Perchoir, 1080 × 1350, rendues en PNG à partir de vraies décisions.
// Question : la carte se lit-elle en vignette dans un fil ?
// Trois mises en page de la direction choisie (fond noir, Geist 700) :
//   A « Anatomie » : languette, résultat énorme, chiffres, hémicycle, titre.
//   B « Titre d'abord » : le sujet en tête, l'hémicycle, résultat en pied.
//   C « Hémicycle en tête » : l'hémicycle en haut, résultat dessous, titre.
//
// Lancer (depuis app/) :
//   PROTO_DATA=<dossier des JSON> PROTO_OUT=<dossier de sortie> \
//     flutter test prototype/social_card/social_card_prototype_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:votedujour/src/hemicycle/hemicycle_places.dart';
import 'package:votedujour/src/hemicycle/hemicycle_seats.dart';
import 'package:votedujour/src/theme.dart';

const _w = 1080.0;
const _h = 1350.0;
const _pad = 72.0;

const _ids = [
  'VTANR5L17V9241', // titre court, adopté
  'VTANR5L17V8693', // titre de 82 caractères, adopté
  'VTANR5L17V8610', // résolution rejetée
  'VTANR5L17V7979', // motion de censure (seuls les pour comptent)
  'VTANR5L17V9759', // budget rejeté
];

const _months = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];

String _date(DateTime d) =>
    '${d.day}\u00A0${_months[d.month - 1]}\u00A0${d.year}';

/// Titre de la cascade : summary.shortTitle, sinon summary.title.
String _title(DecisionSummary d) =>
    d.summary?.shortTitle ?? d.summary?.title ?? 'TITRE À ÉCRIRE';

/// Étape raccourcie : « 1re partie du budget · 1re lecture ».
String _stage(String s) => s
    .replaceAll('Première partie du budget', '1re partie du budget')
    .replaceAll(" à l'AN", '')
    .replaceAll(', ', ' · ');

String _tab(DecisionSummary d) =>
    '${_stage(d.stage ?? '').toUpperCase()} · ${_date(d.date).toUpperCase()}';

const _c = HemicycleColors.dark;

Color _resultColor(VoteResult r) =>
    r == VoteResult.adopte ? _c.pour : _c.contre;

String _resultWord(VoteResult r) =>
    r == VoteResult.adopte ? 'ADOPTÉ' : 'REJETÉ';

/// Chiffres : « 152 pour · 5 contre · 110 abst. » ; motion de censure :
/// seuls les pour comptent, contre la majorité absolue.
List<(String, String)> _figures(DecisionSummary d, VoteTally c) {
  if (d.type == DecisionType.motionDeCensure) {
    return [('${c.pour}', 'pour'), ('289', 'requis')];
  }
  return [
    ('${c.pour}', 'pour'),
    ('${c.contre}', 'contre'),
    ('${c.abstentions}', 'abst.'),
  ];
}

TextStyle _geist(double size, {FontWeight w = FontWeight.w700, Color? c}) =>
    TextStyle(
      fontFamily: geist,
      fontSize: size,
      fontWeight: w,
      color: c ?? _c.ink,
      height: 1,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );

TextStyle _serif(double size) => TextStyle(
  fontFamily: newsreader,
  fontWeight: FontWeight.w400,
  fontVariations: const [ui.FontVariation('wght', 400)],
  fontSize: size,
  color: _c.ink,
  height: 1.1,
  letterSpacing: -0.01 * size,
);

/// Titre jamais tronqué : réduit de 84 à 56 px pour tenir en 3 lignes.
Widget _fitTitle(String text, double width, {double max = 84}) {
  for (var size = max; size >= 48; size -= 4) {
    final p = TextPainter(
      text: TextSpan(text: text, style: _serif(size)),
      textDirection: TextDirection.ltr,
      maxLines: 3,
    )..layout(maxWidth: width);
    if (!p.didExceedMaxLines) return Text(text, style: _serif(size));
  }
  return Text('⚠ $text', style: _serif(48).copyWith(color: _c.contre));
}

Widget _tabStrip(DecisionSummary d) => Container(
  color: _c.surface,
  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
  child: Text(
    _tab(d),
    style: _geist(26, w: FontWeight.w600, c: _c.ink2).copyWith(
      letterSpacing: 1.5,
    ),
  ),
);

Widget _figureRow(DecisionSummary d, VoteTally c, {double size = 64}) => Row(
  crossAxisAlignment: CrossAxisAlignment.baseline,
  textBaseline: TextBaseline.alphabetic,
  children: [
    for (final (i, (n, l)) in _figures(d, c).indexed) ...[
      if (i > 0) SizedBox(width: size * 0.6),
      Text(n, style: _geist(size)),
      const SizedBox(width: 12),
      Text(l, style: _geist(size * 0.45, w: FontWeight.w400, c: _c.ink2)),
    ],
  ],
);

Widget _footer() => Container(
  decoration: BoxDecoration(border: Border(top: BorderSide(color: _c.rule))),
  padding: const EdgeInsets.only(top: 24),
  child: Row(
    children: [
      Text('Le Perchoir', style: _geist(30)),
      const Spacer(),
      Text(
        'Source : Assemblée nationale',
        style: _geist(24, w: FontWeight.w400, c: _c.ink2),
      ),
    ],
  ),
);

/// Mode « couleur = vote, position = groupe » (essai sur 8610).
var _voteMode = false;

// Palette vote de DESIGN.md, mode sombre.
const _vPour = Color(0xFF4FB08F);
const _vContre = Color(0xFFB5461F);
const _vAbst = Color(0xFF9AA2AB);

Widget _hemicycle(DecisionDetail x, double width) => _voteMode
    ? _VoteHemicycle(x, width)
    : HemicycleSeats(
        seats: x.seats!,
        groups: x.groups,
        result: x.decision.result,
        count: x.decision.count!,
        width: width,
      );

/// Hémicycle coloré par le vote, sigles des groupes autour de l'arc.
class _VoteHemicycle extends StatelessWidget {
  const _VoteHemicycle(this.x, this.width);
  final DecisionDetail x;
  final double width;
  static const margin = 56.0;

  @override
  Widget build(BuildContext context) {
    final arcW = width - 2 * margin;
    final arcH = arcW * hemicyclePlan.height / hemicyclePlan.width;
    return CustomPaint(
      size: Size(width, arcH + margin),
      painter: _VotePainter(x, arcW),
    );
  }
}

class _VotePainter extends CustomPainter {
  _VotePainter(this.x, this.arcW);
  final DecisionDetail x;
  final double arcW;

  @override
  void paint(Canvas canvas, Size size) {
    const m = _VoteHemicycle.margin;
    final unit = arcW / hemicyclePlan.width;
    Offset toCanvas(Offset p) => Offset(
      m + (p.dx - hemicyclePlan.left) * unit,
      m + (p.dy - hemicyclePlan.top) * unit,
    );
    final center = toCanvas(
      Offset(hemicyclePlan.center.dx, hemicyclePlan.bottom),
    );
    final fill = Paint()..isAntiAlias = true;
    final angles = <String, List<double>>{};
    var outer = 0.0;
    for (final seat in x.seats!) {
      final plan = hemicyclePlaces[seat.place];
      if (plan == null) continue;
      final c = toCanvas(plan);
      final v = c - center;
      outer = math.max(outer, v.distance);
      angles.putIfAbsent(seat.group, () => []).add(v.direction);
      final (color, alpha) = switch (seat.vote) {
        // Motion de censure : soutien en encre neutre, jamais le vert du
        // « ça passe ».
        SeatVote.pour when x.decision.type == DecisionType.motionDeCensure =>
          (_c.ink, 1.0),
        SeatVote.pour => (_vPour, 1.0),
        SeatVote.contre => (_vContre, 1.0),
        SeatVote.abstention => (_vAbst, 1.0),
        _ => (const Color(0xFF3A3A3A), 0.6),
      };
      canvas.drawCircle(
        c,
        seatRadius * unit,
        fill..color = color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_VotePainter old) => false;
}

/// « 102 votants sur 574 », seulement si moins de la moitié a voté.
Widget _captions(DecisionDetail x) {
  final c = x.decision.count!;
  final votants = c.pour + c.contre + c.abstentions;
  final sieges = x.seats!.length;
  if (x.decision.type == DecisionType.motionDeCensure ||
      votants * 2 >= sieges) {
    return const SizedBox.shrink();
  }
  return Text(
    '$votants votants',
    style: _geist(30, w: FontWeight.w500, c: _c.ink2),
  );
}

Widget _result(DecisionSummary d, double size) => Text(
  _resultWord(d.result),
  style: _geist(size, c: _resultColor(d.result)).copyWith(letterSpacing: -4),
);

/// A « Anatomie ».
Widget variantA(DecisionDetail x) {
  final d = x.decision;
  return Padding(
    padding: const EdgeInsets.all(_pad),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tabStrip(d),
        const Spacer(),
        _result(d, _voteMode ? 150 : 180),
        const SizedBox(height: 16),
        _figureRow(d, d.count!),
        if (_voteMode) ...[const SizedBox(height: 16), _captions(x)],
        const SizedBox(height: 40),
        Center(child: _hemicycle(x, _voteMode ? 860 : 820)),
        const SizedBox(height: 36),
        _fitTitle(_title(d), _w - 2 * _pad, max: 68),
        const Spacer(),
        _footer(),
      ],
    ),
  );
}

/// B « Titre d'abord ».
Widget variantB(DecisionDetail x) {
  final d = x.decision;
  return Padding(
    padding: const EdgeInsets.all(_pad),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tabStrip(d),
        SizedBox(height: _voteMode ? 24 : 40),
        _fitTitle(_title(d), _w - 2 * _pad, max: _voteMode ? 72 : 84),
        const Spacer(),
        Center(child: _hemicycle(x, 840)),
        if (_voteMode) ...[const SizedBox(height: 16), _captions(x)],
        const Spacer(),
        Container(
          width: double.infinity,
          color: _resultColor(d.result),
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _resultWord(d.result),
                style: _geist(120, c: _c.background).copyWith(
                  letterSpacing: -3,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                [
                  for (final (n, l) in _figures(d, d.count!))
                    if (!(l == 'abst.' && n == '0')) '$n\u00A0$l',
                ].join('  ·  '),
                style: _geist(54, c: _c.background),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        _footer(),
      ],
    ),
  );
}

/// C « Hémicycle en tête » : l'hémicycle déborde des marges.
Widget variantC(DecisionDetail x) {
  final d = x.decision;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 56),
      Center(child: _hemicycle(x, 900)),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(_pad, 8, _pad, _pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: _result(d, 160)),
              const SizedBox(height: 12),
              Center(child: _figureRow(d, d.count!, size: 56)),
              const Spacer(),
              _tabStrip(d),
              const SizedBox(height: 24),
              _fitTitle(_title(d), _w - 2 * _pad, max: 64),
              const SizedBox(height: 40),
              _footer(),
            ],
          ),
        ),
      ),
    ],
  );
}

final _variants = {'A': variantA, 'B': variantB, 'C': variantC};

Future<void> _loadFonts() async {
  Future<ByteData> f(String name) async =>
      ByteData.sublistView(File('assets/fonts/$name').readAsBytesSync());
  await (FontLoader(geist)
        ..addFont(f('Geist-Regular.ttf'))
        ..addFont(f('Geist-Medium.ttf'))
        ..addFont(f('Geist-SemiBold.ttf'))
        ..addFont(f('Geist-Bold.ttf')))
      .load();
  await (FontLoader(newsreader)..addFont(f('Newsreader.ttf'))).load();
}

Future<void> _shoot(WidgetTester tester, Widget card, Size size, String path)
async {
  final key = GlobalKey();
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.dark),
      home: RepaintBoundary(
        key: key,
        child: Material(color: _c.background, child: card),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  final data = Platform.environment['PROTO_DATA'];
  final out = Platform.environment['PROTO_OUT'];

  testWidgets('cartes réseau social', (tester) async {
    await tester.runAsync(_loadFonts);
    final details = [
      for (final id in _ids)
        DecisionDetail.fromJson(
          jsonDecode(File('$data/$id.json').readAsStringSync()),
        ),
    ];
    for (final MapEntry(key: v, value: build) in _variants.entries) {
      for (final x in details) {
        await _shoot(
          tester,
          SizedBox(width: _w, height: _h, child: build(x)),
          const Size(_w, _h),
          '$out/$v-${x.decision.numero}.png',
        );
      }
      // Planche « fil » : chaque carte à 340 px de large, la taille d'une
      // image dans un fil Bluesky sur téléphone (vue à 1 px = 1 pt).
      const thumb = 340.0;
      await _shoot(
        tester,
        Wrap(
          spacing: 24,
          runSpacing: 24,
          children: [
            for (final x in details)
              SizedBox(
                width: thumb,
                height: thumb * _h / _w,
                child: FittedBox(
                  child: SizedBox(width: _w, height: _h, child: build(x)),
                ),
              ),
          ],
        ),
        Size(3 * thumb + 2 * 24, 2 * thumb * _h / _w + 24),
        '$out/fil-$v.png',
      );
    }
    // Essai « couleur = vote » : toutes les décisions, A et B, plus la
    // comparaison côte à côte de 8610.
    for (final mode in [false, true]) {
      _voteMode = mode;
      for (final MapEntry(key: v, value: build) in {
        'A': variantA,
        'B': variantB,
      }.entries) {
        for (final x in details) {
          if (mode) {
            await _shoot(
              tester,
              SizedBox(width: _w, height: _h, child: build(x)),
              const Size(_w, _h),
              '$out/$v-vote-${x.decision.numero}.png',
            );
          }
        }
      }
    }
    _voteMode = true;
    for (final MapEntry(key: v, value: build) in {
      'A': variantA,
      'B': variantB,
    }.entries) {
      const thumb = 340.0;
      await _shoot(
        tester,
        Wrap(
          spacing: 24,
          runSpacing: 24,
          children: [
            for (final x in details)
              SizedBox(
                width: thumb,
                height: thumb * _h / _w,
                child: FittedBox(
                  child: SizedBox(width: _w, height: _h, child: build(x)),
                ),
              ),
          ],
        ),
        Size(3 * thumb + 2 * 24, 2 * thumb * _h / _w + 24),
        '$out/fil-vote-$v.png',
      );
    }
    const t = 480.0;
    Widget pair(Widget Function(DecisionDetail) build, DecisionDetail x) =>
        SizedBox(
          width: t,
          height: t * _h / _w,
          child: FittedBox(
            child: SizedBox(width: _w, height: _h, child: build(x)),
          ),
        );
    final r = details.firstWhere((x) => x.decision.numero == 8610);
    Widget cell(bool mode, Widget Function(DecisionDetail) b) =>
        Builder(builder: (_) {
          _voteMode = mode;
          return pair(b, r);
        });
    for (final MapEntry(key: v, value: b) in {
      'A': variantA,
      'B': variantB,
    }.entries) {
      await _shoot(
        tester,
        Row(children: [cell(false, b), const SizedBox(width: 24), cell(true, b)]),
        const Size(2 * t + 24, t * _h / _w),
        '$out/compare-$v-8610.png',
      );
    }
    _voteMode = false;
  }, skip: data == null || out == null);
}
