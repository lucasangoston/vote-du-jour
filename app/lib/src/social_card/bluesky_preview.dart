import 'package:flutter/material.dart';

import '../hemicycle/hemicycle_logo.dart';
import '../theme.dart';

/// Largeur de l'aperçu, en points : un téléphone courant.
const blueskyPreviewWidth = 390.0;

// Couleurs du thème sombre de Bluesky (approchées) : l'aperçu montre la
// place du post dans un fil, pas une copie exacte de l'app.
const _background = Color(0xFF161E27);
const _text = Color(0xFFF1F3F5);
const _muted = Color(0xFF8D9BAA);
const _link = Color(0xFF208BFE);
const _divider = Color(0xFF2E4052);

/// Aperçu d'un post Le Perchoir dans un fil Bluesky mobile (#122) : avatar,
/// nom, `@leperchoir.app`, [text] (liens et mots-dièse en couleur de lien),
/// la carte [card] (PNG) à son format 4:5, angles arrondis comme dans l'app,
/// puis les [replies] du fil, reliées par le trait des fils de Bluesky.
class BlueskyPreview extends StatelessWidget {
  const BlueskyPreview({
    super.key,
    required this.text,
    required this.card,
    this.replies = const [],
  });

  final String text;
  final ImageProvider card;

  /// Réponses publiées sous le post, dans l'ordre.
  final List<String> replies;

  static const handle = 'leperchoir.app';

  static const _body = TextStyle(
    fontFamily: geist,
    fontSize: 15,
    height: 1.35,
    color: _text,
  );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _background,
      child: Container(
        width: blueskyPreviewWidth,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _divider)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _post(text, image: card, threaded: replies.isNotEmpty),
            for (final (i, reply) in replies.indexed)
              _post(reply, threaded: i < replies.length - 1),
          ],
        ),
      ),
    );
  }

  /// Un post du fil ; [threaded] : un autre le suit, le trait descend de
  /// l'avatar jusqu'au suivant.
  Widget _post(String text, {ImageProvider? image, required bool threaded}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const HemicycleLogo.small(
                  width: 28,
                  color: Colors.white,
                ),
              ),
              if (threaded)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: _divider,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: threaded ? 14 : 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Le Perchoir ',
                          style: _body.copyWith(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: '@$handle · 1 min',
                          style: _body.copyWith(color: _muted),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text.rich(TextSpan(children: _rich(text)), style: _body),
                  if (image != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AspectRatio(
                        aspectRatio: 4 / 5,
                        child: Image(image: image, fit: BoxFit.cover),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final icon in const [
                        Icons.chat_bubble_outline,
                        Icons.repeat,
                        Icons.favorite_border,
                        Icons.more_horiz,
                      ]) ...[
                        Icon(icon, size: 18, color: _muted),
                        const Spacer(),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Ce que Bluesky colore : une adresse, `leperchoir.app`, le lien du
  // scrutin écrit sans `https://`, un mot-dièse.
  static final _linked = RegExp(
    r'https?://\S+|assemblee-nationale\.fr/[^\s.,;]+(?:\.[^\s.,;]+)*'
    r'|leperchoir\.app|(?<![\p{L}\p{N}])#[\p{L}][\p{L}\p{N}_]*',
    unicode: true,
  );

  /// [text], avec ses liens et ses mots-dièse en couleur de lien.
  static List<InlineSpan> _rich(String text) {
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in _linked.allMatches(text)) {
      spans
        ..add(TextSpan(text: text.substring(at, m.start)))
        ..add(
          TextSpan(
            text: m[0],
            style: _body.copyWith(color: _link),
          ),
        );
      at = m.end;
    }
    return spans..add(TextSpan(text: text.substring(at)));
  }
}
