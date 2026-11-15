import 'package:test/test.dart';
import 'package:vote_job/vote_job.dart';

final _day = DateTime.utc(2026, 11, 14);

const _ready = Draft(
  decisionId: 'VTANR5L17V8610',
  sourceUrl: 'https://www.assemblee-nationale.fr/dyn/17/scrutins/8610',
  title: 'Donner aux acheteurs publics un critère de priorité nationale',
  text:
      'Rejeté : Donner aux acheteurs publics…\n151 pour · 187 contre.\n'
      'leperchoir.app',
  alt: 'Carte Le Perchoir. Rejeté, 151 pour, 187 contre.',
  imageUrl: 'https://pub.r2.dev/content/2026-11-14/VTANR5L17V8610.png',
);

const _toTitle = Draft(
  decisionId: 'VTANR5L17V8693',
  sourceUrl: 'https://www.assemblee-nationale.fr/dyn/17/scrutins/8693',
  title: null,
);

void main() {
  test('titre et clé de l\'image', () {
    expect(dailyIssueTitle(_day), 'Posts du 14 novembre 2026');
    expect(
      draftImageKey(_day, 'VTANR5L17V8610'),
      'content/2026-11-14/VTANR5L17V8610.png',
    );
  });

  group('corps de l\'issue', () {
    final body = renderDailyIssue(_day, [_ready, _toTitle]);

    test('un bloc par brouillon : case, image, textes, vérification', () {
      expect(body, contains('<!-- content-factory:v1 day:2026-11-14 -->'));
      expect('- [ ] Publier ce post'.allMatches(body), hasLength(2));
      expect(body, contains('![Carte](${_ready.imageUrl})'));
      expect(body, contains('```text\n${_ready.text}\n```'));
      expect(body, contains('```text\n${_ready.alt}\n```'));
      expect(body, contains('(${_ready.text!.runes.length} / 300)'));
      expect(
        body,
        contains('[page officielle du scrutin](${_ready.sourceUrl})'),
      );
    });

    test('titre à écrire : champ titre vide, ni image ni texte', () {
      final block = body.substring(body.indexOf('decision:VTANR5L17V8693'));
      expect(block, contains('### Titre à écrire'));
      expect(block, contains('**Titre**\n\n```text\n\n```'));
      expect(block, isNot(contains('![Carte]')));
    });

    test('relu tel quel : les mêmes brouillons, non cochés', () {
      final drafts = parseDailyIssue(body);
      expect(drafts, hasLength(2));
      final ready = drafts.first;
      expect(ready.decisionId, _ready.decisionId);
      expect(ready.title, _ready.title);
      expect(ready.text, _ready.text);
      expect(ready.alt, _ready.alt);
      expect(ready.imageUrl, _ready.imageUrl);
      expect(ready.sourceUrl, _ready.sourceUrl);
      expect(ready.checked, isFalse);
      expect(ready.postUrl, isNull);
      expect(drafts.last.needsTitle, isTrue);
    });

    test('relu après édition : case cochée, texte corrigé, titre écrit', () {
      final edited = body
          .replaceFirst('- [ ] Publier ce post', '- [x] Publier ce post')
          .replaceFirst('151 pour · 187 contre.', '151 pour, 187 contre.')
          .replaceFirst(
            '**Titre**\n\n```text\n\n```',
            '**Titre**\n\n```text\nTitre-restaurant dématérialisé\n```',
          );
      final drafts = parseDailyIssue(edited);
      expect(drafts.first.checked, isTrue);
      expect(drafts.first.text, contains('151 pour, 187 contre.'));
      expect(drafts.last.checked, isFalse);
      expect(drafts.last.title, 'Titre-restaurant dématérialisé');
      expect(drafts.last.needsTitle, isFalse);
      // L'original caché ne change pas avec l'édition.
      expect(originalDraft(edited, _ready.decisionId)!['text'], _ready.text);
      expect(originalDraft(edited, _toTitle.decisionId)!['title'], isNull);
    });

    test('lien du post publié relu', () {
      final posted = body.replaceFirst(
        '<!-- original:',
        'Publié : https://bsky.app/profile/leperchoir.app/post/abc\n\n'
            '<!-- original:',
      );
      expect(
        parseDailyIssue(posted).first.postUrl,
        'https://bsky.app/profile/leperchoir.app/post/abc',
      );
    });

    test('un bloc sans original ni source est ignoré', () {
      expect(
        parseDailyIssue(
          '<!-- decision:X -->\n### abîmé\n- [x] Publier ce post',
        ),
        isEmpty,
      );
    });
  });

  test('décisions déjà traitées : seulement les issues de la factory', () {
    final body = renderDailyIssue(_day, [_ready, _toTitle]);
    expect(
      handledDecisionIds([
        body,
        'Une autre issue qui cite <!-- decision:AUTRE -->',
      ]),
      {'VTANR5L17V8610', 'VTANR5L17V8693'},
    );
  });

  test('lien du post écrit sous la case, une seule fois', () {
    final body = renderDailyIssue(_day, [_ready, _toTitle]);
    const url = 'https://bsky.app/profile/leperchoir.app/post/r0';
    final marked = markPublished(body, _ready.decisionId, url);
    expect(marked, contains('- [ ] Publier ce post\n\nPublié : $url\n'));
    final drafts = parseDailyIssue(marked);
    expect(drafts.first.postUrl, url);
    expect(drafts.last.postUrl, isNull);
    expect(markPublished(marked, _ready.decisionId, 'autre'), marked);
    expect(markPublished(body, 'inconnu', url), body);
  });
}
