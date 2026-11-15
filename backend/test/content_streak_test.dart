import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';
import 'package:vote_job/vote_job.dart';

DecisionDetail _fixture(String id) => DecisionDetail.fromJson(
  jsonDecode(File('test/fixtures/content/detail_$id.json').readAsStringSync()),
);

final _detail = _fixture('8610');
const _title = 'Donner aux acheteurs publics un critère de priorité nationale';
final _text = postText(_detail, title: _title);

Draft _draft(String id, {bool needsTitle = false}) => needsTitle
    ? Draft(decisionId: id, sourceUrl: 'https://an.test/$id', title: null)
    : Draft(
        decisionId: id,
        sourceUrl: 'https://an.test/$id',
        title: _title,
        text: _text,
        alt: altText(_detail, title: _title),
        imageUrl: 'https://pub.test/$id.png',
      );

/// Issue du [day] novembre, chaque brouillon de [ids] publié ; [edit]
/// modifie le corps avant publication (correction de l'utilisateur).
String _issue(
  int day,
  List<String> ids, {
  String Function(String)? edit,
  bool needsTitle = false,
}) {
  var body = renderDailyIssue(DateTime.utc(2026, 11, day), [
    for (final id in ids) _draft(id, needsTitle: needsTitle),
  ]);
  if (edit != null) body = edit(body);
  for (final id in ids) {
    body = markPublished(body, id, 'https://bsky.app/post/$id');
  }
  return body;
}

void main() {
  test('posts publiés intacts : comptés', () {
    expect(
      uncorrectedStreak([
        _issue(1, ['A', 'B']),
        _issue(2, ['C']),
      ]),
      3,
    );
  });

  test('brouillon non publié : pas compté', () {
    final body = renderDailyIssue(DateTime.utc(2026, 11, 1), [_draft('A')]);
    expect(uncorrectedStreak([body]), 0);
  });

  test('retouche de typographie seule : pas une correction', () {
    // Le texte généré porte des espaces insécables : la retouche change
    // bien le texte.
    expect(_text, matches(RegExp('[\u00A0\u202F]')));
    final retouched = _issue(
      1,
      ['A'],
      // Espace insécable remplacée par une espace ordinaire, apostrophe
      // courbe par une droite, espace en fin de ligne.
      edit: (b) => b
          .replaceAll(' ', ' ')
          .replaceAll(' ', ' ')
          .replaceAll('’', "'")
          .replaceFirst('leperchoir.app\n```', 'leperchoir.app \n```'),
    );
    expect(publishedPosts(retouched).single.corrected, isFalse);
    expect(uncorrectedStreak([retouched]), 1);
  });

  test('texte corrigé : le compteur repart de zéro', () {
    final corrected = _issue(
      2,
      ['C'],
      edit: (b) =>
          b.replaceFirst(_text, _text.replaceFirst('Rejeté', 'Rejeté.')),
    );
    expect(publishedPosts(corrected).single.corrected, isTrue);
    expect(
      uncorrectedStreak([
        _issue(3, ['D', 'E']),
        corrected,
        _issue(1, ['A', 'B']),
      ]),
      2,
    );
    expect(
      uncorrectedStreak([
        _issue(1, ['A']),
        corrected,
      ]),
      0,
    );
  });

  test('titre écrit à la main : une correction', () {
    final written = _issue(1, ['A'], needsTitle: true);
    expect(publishedPosts(written).single.corrected, isTrue);
  });

  test('ordre des posts : jour, puis bloc', () {
    final corrected = _issue(
      1,
      ['A', 'B'],
      edit: (b) {
        // Seul le premier bloc (A) est corrigé : B, après lui, compte.
        final at = b.indexOf(_text);
        return b.replaceRange(at, at + _text.length, '$_text !');
      },
    );
    expect(uncorrectedStreak([corrected]), 1);
  });

  test('compteur affiché en tête de l\'issue du jour', () {
    final day = DateTime.utc(2026, 11, 14);
    expect(
      renderDailyIssue(day, [_draft('A')], streak: 12),
      contains('Compteur : 12 / 30 posts publiés sans correction'),
    );
    expect(
      renderDailyIssue(day, [_draft('A')], streak: 30),
      contains('peut passer en publication automatique'),
    );
    expect(renderDailyIssue(day, [_draft('A')]), isNot(contains('Compteur')));
  });

  group('publication automatique', () {
    // 8610 a des arguments : sans eux, ni solennel ni censure.
    final plain = _detail.withArguments(null);
    final d = plain.decision;

    test('au-delà de 30 sans correction', () {
      expect(requiresManualReview(plain), isFalse);
      expect(canAutoPublish(plain, streak: 29), isFalse);
      expect(canAutoPublish(plain, streak: 30), isTrue);
    });

    test('exceptions toujours validées à la main, même au-delà de 30', () {
      final solennel = plain.withDecision(
        DecisionSummary.tryFromJson({...d.toJson(), 'solennel': true})!,
      );
      final censure = plain.withDecision(
        DecisionSummary.tryFromJson({
          ...d.toJson(),
          'type': 'motion_de_censure',
        })!,
      );
      expect(_detail.arguments, isNotNull);
      for (final detail in [solennel, censure, _detail]) {
        expect(requiresManualReview(detail), isTrue);
        expect(canAutoPublish(detail, streak: 100), isFalse);
      }
    });
  });
}
