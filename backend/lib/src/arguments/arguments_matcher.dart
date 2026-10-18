import 'package:vote_contract/vote_contract.dart';

import 'compte_rendu.dart';

/// Types de décision qui peuvent recevoir des arguments : les votes sur
/// l'ensemble d'un texte (ou sur son article unique) et les propositions de
/// résolution, seuls précédés d'explications de vote suivies d'un « Vote
/// sur l'ensemble ».
const argumentDecisionTypes = {
  DecisionType.ensembleTexte,
  DecisionType.resolution,
};

/// Une décision peut-elle recevoir des arguments : confirmée (vote par
/// groupe du jeu de données), au scrutin public, d'un type de
/// [argumentDecisionTypes] ?
bool isArgumentCandidate(DecisionDetail detail) =>
    detail.decision.status == DecisionStatus.confirmee &&
    detail.decision.voteMode == VoteMode.scrutinPublic &&
    argumentDecisionTypes.contains(detail.decision.type) &&
    detail.count != null &&
    detail.groups.isNotEmpty;

/// Explications de vote rattachées à une décision, classées par camp selon
/// la position du groupe de chaque orateur dans le scrutin.
class AttachedExplanations {
  const AttachedExplanations({
    required this.compteRendu,
    required this.pour,
    required this.contre,
    required this.abstention,
  });

  final CompteRendu compteRendu;
  final List<GroupSpeech> pour;
  final List<GroupSpeech> contre;
  final List<GroupSpeech> abstention;

  bool get isEmpty => pour.isEmpty && contre.isEmpty && abstention.isEmpty;
}

/// Ce qu'un groupe a dit (ses orateurs réunis), et sa référence d'organe.
class GroupSpeech {
  const GroupSpeech({
    required this.group,
    required this.organeRef,
    required this.speakers,
    required this.text,
  });

  /// Sigle du groupe dans le vote par groupe (« LFI-NFP »).
  final String group;
  final String organeRef;
  final List<String> speakers;
  final String text;
}

/// Rattache chaque décision de [decisions] à sa section d'explications de
/// vote dans [comptesRendus].
///
/// Une décision et un vote sur l'ensemble du compte rendu se correspondent
/// si la séance tombe le jour de la décision et si le compte rendu nomme le
/// même texte, avec les mêmes voix quand il donne le résultat ([voteFits]). Le rattachement n'est retenu que s'il est
/// réciproque et unique : la décision ne correspond qu'à ce vote, et ce
/// vote qu'à cette décision. En cas de doute, la décision n'a rien.
///
/// Une section commune à plusieurs textes vaut pour chacun d'eux. Les
/// interventions sont classées selon la position du groupe de l'orateur dans
/// le scrutin ; un orateur dont le groupe est inconnu, non inscrit, partagé
/// ou sans vote est ignoré. Une décision sans intervention classée n'est
/// pas dans le résultat.
Map<String, AttachedExplanations> attachExplanations(
  List<DecisionDetail> decisions,
  List<CompteRendu> comptesRendus,
) {
  final votes =
      <({CompteRendu cr, ExplanationSection section, WholeVote vote})>[
        for (final cr in comptesRendus)
          for (final section in cr.sections)
            for (final vote in section.votes)
              (cr: cr, section: section, vote: vote),
      ];
  // Toutes les décisions du jour comptent pour l'unicité, même celles qui ne
  // peuvent pas recevoir d'arguments.
  bool fits(DecisionDetail d, int v) =>
      votes[v].cr.date == d.decision.date &&
      voteFits(d, votes[v].section, votes[v].vote);
  final result = <String, AttachedExplanations>{};
  for (final d in decisions) {
    if (!isArgumentCandidate(d)) continue;
    final matching = [
      for (var v = 0; v < votes.length; v++)
        if (fits(d, v)) v,
    ];
    if (matching.length != 1) continue;
    final v = matching.single;
    final rivals = decisions.where((other) => fits(other, v)).length;
    if (rivals != 1) continue;
    final attached = classifySpeeches(d, votes[v].cr, votes[v].section);
    if (!attached.isEmpty) result[d.decision.id] = attached;
  }
  return result;
}

/// La décision [d] correspond-elle au vote [vote] de la section [section]
/// (même date vérifiée à part) ?
///
/// - Nature du texte : loi organique ou non, résolution ou non, lue dans la
///   phrase qui met le texte aux voix et le titre du vote (une loi et sa loi
///   organique sont souvent examinées ensemble, sous des titres voisins).
/// - Intitulé : les mots significatifs de l'intitulé officiel se retrouvent
///   dans le texte le plus précis du compte rendu ([voteEvidence]).
/// - Voix : quand le compte rendu donne le résultat, les voix pour et contre
///   sont les mêmes ; l'intitulé peut alors être retrouvé à moitié
///   ([titleCoverageWithCount]), ou le titre du dossier presque entièrement ;
///   sans résultat lisible, l'intitulé doit l'être presque entièrement
///   ([titleCoverage]).
bool voteFits(DecisionDetail d, ExplanationSection section, WholeVote vote) {
  final title = _officialWords(d.decision.officialTitle);
  final nature = normalizeForMatching(
    '${vote.announcement ?? ''} ${vote.heading}',
  );
  final official = normalizeForMatching(d.decision.officialTitle);
  for (final word in ['organique', 'resolution']) {
    if (official.contains(word) != nature.contains(word)) return false;
  }
  final result = vote.result;
  final count = d.count;
  final sameCount =
      result != null &&
      count != null &&
      result.pour == count.pour &&
      result.contre == count.contre;
  if (result != null && count != null && !sameCount) return false;
  final evidence = voteEvidence(section, vote);
  if (titleCoverageIn(title, evidence) >=
      (sameCount ? titleCoverageWithCount : titleCoverage)) {
    return true;
  }
  // Le titre du dossier (« Statut de l'élu local ») est souvent celui de la
  // discussion ; avec les mêmes voix, il doit s'y retrouver presque
  // entièrement.
  final short = d.decision.shortTitle;
  return sameCount &&
      short != null &&
      titleCoverageIn(
            _significantWords(normalizeForMatching(short)),
            evidence,
          ) >=
          titleCoverage;
}

/// Part minimale des mots significatifs de l'intitulé officiel à retrouver
/// quand le résultat du scrutin n'est pas lisible dans le compte rendu.
const titleCoverage = 0.8;

/// Même part, quand les voix pour et contre du compte rendu sont celles du
/// scrutin.
const titleCoverageWithCount = 0.5;

/// Texte du compte rendu qui nomme le texte voté, du plus précis au moins
/// précis : la phrase qui le met aux voix (« Je mets aux voix l'ensemble de
/// la proposition de loi organique visant à… »), sinon le titre du vote
/// (« Vote sur l'ensemble (droit à l'aide à mourir) »), sinon le titre de la
/// discussion. La phrase « Je mets aux voix l'ensemble de la proposition de
/// loi. » ne nomme rien : on passe au suivant.
String voteEvidence(ExplanationSection section, WholeVote vote) {
  for (final text in [vote.announcement, vote.heading]) {
    if (text != null &&
        _significantWords(normalizeForMatching(text)).length >= 3) {
      return text;
    }
  }
  return section.discussionTitle;
}

/// Part des mots [title] présents dans [text].
double titleCoverageIn(Set<String> title, String text) {
  if (title.isEmpty) return 0;
  final available = _significantWords(normalizeForMatching(text));
  return title.where(available.contains).length / title.length;
}

/// Mots significatifs d'un intitulé officiel, sans la mention de la lecture
/// (« (première lecture) »).
Set<String> _officialWords(String officialTitle) => _significantWords(
  normalizeForMatching(
    officialTitle.replaceAll(
      RegExp(r'\([^()]*(lecture|paritaire)[^()]*\)'),
      '',
    ),
  ),
);

const _ignoredWords = {
  'les',
  'des',
  'aux',
  'une',
  'par',
  'sur',
  'dans',
  'pour',
  'avec',
  'que',
  'qui',
  'son',
  'ses',
  'leur',
  'leurs',
  'ensemble',
  'proposition',
  'projet',
  'loi',
  'organique',
  'resolution',
  'article',
  'unique',
  'texte',
  'mets',
  'voix',
  'vote',
  'lecture',
  'premiere',
  'deuxieme',
  'nouvelle',
  'definitive',
  'commission',
  'mixte',
  'paritaire',
  'europeenne',
  'visant',
  'portant',
  'tendant',
  'relatif',
  'relative',
  'relatifs',
  'relatives',
  'ordinaire',
};

Set<String> _significantWords(String normalized) => {
  for (final w in normalized.split(RegExp(r"[^a-z0-9]+")))
    if (w.length >= 3 && !_ignoredWords.contains(w)) w,
};

/// Classe les interventions de [section] par camp, selon la position dans
/// le scrutin [d] du groupe de chaque orateur (sigle comparé sans la casse).
AttachedExplanations classifySpeeches(
  DecisionDetail d,
  CompteRendu cr,
  ExplanationSection section,
) {
  final byGroup = <String, GroupVoteDetail>{
    for (final g in d.groups)
      if (g.abbreviation case final a?) a.toLowerCase(): g,
  };
  final speeches = <GroupPosition, Map<String, _Speeches>>{};
  for (final s in section.speeches) {
    final group = byGroup[s.group.trim().toLowerCase()];
    if (group == null || group.abbreviation == 'NI') continue;
    final position = group.position;
    if (position != GroupPosition.pour &&
        position != GroupPosition.contre &&
        position != GroupPosition.abstention) {
      continue;
    }
    speeches
        .putIfAbsent(position, () => {})
        .putIfAbsent(group.organeRef, () => _Speeches(group))
        .add(s);
  }
  List<GroupSpeech> side(GroupPosition p) => [
    for (final s in (speeches[p] ?? const <String, _Speeches>{}).values)
      s.build(),
  ];
  return AttachedExplanations(
    compteRendu: cr,
    pour: side(GroupPosition.pour),
    contre: side(GroupPosition.contre),
    abstention: side(GroupPosition.abstention),
  );
}

class _Speeches {
  _Speeches(this.group);

  final GroupVoteDetail group;
  final speakers = <String>[];
  final texts = <String>[];

  void add(Speech s) {
    if (!speakers.contains(s.speaker)) speakers.add(s.speaker);
    texts.add(s.text);
  }

  GroupSpeech build() => GroupSpeech(
    group: group.abbreviation!,
    organeRef: group.organeRef,
    speakers: speakers,
    text: texts.join(' '),
  );
}
