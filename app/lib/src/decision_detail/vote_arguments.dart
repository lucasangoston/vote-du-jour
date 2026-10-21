import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vote_contract/vote_contract.dart';

import '../decision_list_page.dart' show formatShortFrenchDate;
import '../hemicycle/line_icon.dart';
import '../theme.dart';
import 'group_logo.dart';

/// Intertitre des arguments des groupes (ticket #35).
const argumentsHeading = 'Pourquoi ils ont voté ainsi';

/// Titre de la carte d'un camp.
String argumentsSideLabel(GroupPosition position) => switch (position) {
  GroupPosition.pour => 'Pour',
  GroupPosition.contre => 'Contre',
  GroupPosition.abstention => 'Abstention',
  GroupPosition.partage || GroupPosition.nonVotant => '',
};

/// Libellé du lien vers le compte rendu, dans la ligne de source.
const argumentsSourceLink = 'compte rendu';

/// « Résumé par IA · séance du 13 oct. » (suivi du lien vers le compte
/// rendu).
String argumentsSourceLead(ArgumentsSource source) =>
    'Résumé par IA · séance du '
    '${formatShortFrenchDate(source.date, withYear: false)}';

/// Cartes « Pour », « Contre » et « Abstention » (sans
/// l'intertitre), un camp sans argument n'a pas de carte ; puis la ligne
/// de source, qui ouvre le compte rendu de la séance.
class VoteArguments extends StatelessWidget {
  const VoteArguments(this.arguments, {super.key});

  final DecisionArguments arguments;

  @override
  Widget build(BuildContext context) {
    final sides = [
      (GroupPosition.pour, arguments.pour),
      (GroupPosition.contre, arguments.contre),
      (GroupPosition.abstention, arguments.abstention),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (position, items) in sides)
          if (items.isNotEmpty) ...[
            _SideCard(position, items),
            const SizedBox(height: 12),
          ],
        _SourceLine(arguments.source),
      ],
    );
  }
}

class _SideCard extends StatelessWidget {
  const _SideCard(this.position, this.items);

  final GroupPosition position;
  final List<GroupArgument> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (glyph, color) = switch (position) {
      GroupPosition.pour => (LineGlyph.check, colors.pour),
      GroupPosition.contre => (LineGlyph.cross, colors.contre),
      _ => (LineGlyph.dash, colors.ink2),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  LineIcon(glyph, size: 18, strokeWidth: 2.4, color: color),
                  const SizedBox(width: 8),
                  Text(
                    argumentsSideLabel(position),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (final item in items) _ArgumentItem(item),
        ],
      ),
    );
  }
}

/// Un argument : petit logo du groupe, sigle en gras, puis le texte.
class _ArgumentItem extends StatelessWidget {
  const _ArgumentItem(this.argument);

  final GroupArgument argument;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: ExcludeSemantics(child: _SmallLogo(argument.group)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${argument.group} ',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colors.ink,
                    ),
                  ),
                  TextSpan(text: argument.text),
                ],
              ),
              style: TextStyle(
                fontSize: 14.5,
                height: 1.45,
                color: colors.body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Logo du groupe en 36 × 24 (sur une plaque claire en sombre), ou petite
/// vignette à sigle.
class _SmallLogo extends StatelessWidget {
  const _SmallLogo(this.abbreviation);

  final String abbreviation;

  static const _width = 36.0;
  static const _height = 24.0;
  static const _graphite = Color(0xFF4F5761);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final asset = groupLogoAssets[abbreviation];
    if (asset == null) {
      return Container(
        width: _width,
        height: _height,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: dark ? HemicycleColors.dark.abstention : _graphite,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            abbreviation,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFFFFFFFF),
            ),
          ),
        ),
      );
    }
    if (!dark) {
      return Image.asset(
        asset,
        width: _width,
        height: _height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
    }
    return Container(
      width: _width,
      height: _height,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        color: HemicycleColors.light.background,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// « Résumé par IA · séance du 13 oct. (compte rendu) » : toucher la ligne
/// ouvre le compte rendu.
class _SourceLine extends StatelessWidget {
  const _SourceLine(this.source);

  final ArgumentsSource source;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      link: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => launchUrl(
          Uri.parse(source.url),
          mode: LaunchMode.externalApplication,
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '${argumentsSourceLead(source)} ('),
              TextSpan(
                text: argumentsSourceLink,
                style: TextStyle(
                  decoration: TextDecoration.underline,
                  decorationColor: colors.ink2,
                ),
              ),
              const TextSpan(text: ')'),
            ],
          ),
          style: TextStyle(fontSize: 12.5, height: 1.5, color: colors.ink2),
        ),
      ),
    );
  }
}
