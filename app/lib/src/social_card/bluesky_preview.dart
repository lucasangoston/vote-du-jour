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
/// nom, `@leperchoir.app`, [text] (le lien en couleur de lien), puis la carte
/// [card] (PNG) à son format 4:5, angles arrondis comme dans l'app.
class BlueskyPreview extends StatelessWidget {
  const BlueskyPreview({super.key, required this.text, required this.card});

  final String text;
  final ImageProvider card;

  static const handle = 'leperchoir.app';

  @override
  Widget build(BuildContext context) {
    final body = const TextStyle(
      fontFamily: geist,
      fontSize: 15,
      height: 1.35,
      color: _text,
    );
    return Material(
      color: _background,
      child: Container(
        width: blueskyPreviewWidth,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _divider)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const HemicycleLogo.small(width: 28, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Le Perchoir ',
                          style: body.copyWith(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: '@$handle · 1 min',
                          style: body.copyWith(color: _muted),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(children: _withLink(text, body)),
                    style: body,
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 4 / 5,
                      child: Image(image: card, fit: BoxFit.cover),
                    ),
                  ),
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
          ],
        ),
      ),
    );
  }

  /// Le texte, avec `leperchoir.app` en couleur de lien.
  static List<InlineSpan> _withLink(String text, TextStyle style) {
    final parts = text.split(handle);
    return [
      for (var i = 0; i < parts.length; i++) ...[
        TextSpan(text: parts[i]),
        if (i < parts.length - 1)
          TextSpan(
            text: handle,
            style: style.copyWith(color: _link),
          ),
      ],
    ];
  }
}
