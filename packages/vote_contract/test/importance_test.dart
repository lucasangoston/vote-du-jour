import 'package:test/test.dart';
import 'package:vote_contract/vote_contract.dart';

/// Décision de test : par défaut, un texte de compromis (CMP) confirmé.
DecisionSummary _decision({
  DecisionType type = DecisionType.ensembleTexte,
  DecisionStatus status = DecisionStatus.confirmee,
  VoteResult result = VoteResult.adopte,
  VoteMode voteMode = VoteMode.scrutinPublic,
  String? stage = cmpStage,
  bool solennel = false,
}) => DecisionSummary(
  id: 'A',
  numero: voteMode == VoteMode.scrutinPublic ? 100 : null,
  voteMode: voteMode,
  type: type,
  status: status,
  result: result,
  date: DateTime.utc(2026, 10, 15),
  officialTitle: "l'ensemble du projet de loi",
  sourceUrl: 'https://www.assemblee-nationale.fr/dyn/17/scrutins/100',
  stage: stage,
  solennel: solennel,
);

void main() {
  group('isImportantDecision', () {
    test('scrutin solennel, quelle que soit l’étape', () {
      expect(
        isImportantDecision(
          _decision(stage: "1re lecture à l'AN", solennel: true),
        ),
        isTrue,
      );
      expect(
        isImportantDecision(_decision(stage: "1re lecture à l'AN")),
        isFalse,
      );
    });

    test('motion de censure, adoptée ou rejetée', () {
      for (final result in VoteResult.values) {
        expect(
          isImportantDecision(
            _decision(
              type: DecisionType.motionDeCensure,
              result: result,
              stage: 'Motion de censure',
            ),
          ),
          isTrue,
        );
      }
    });

    test('lecture définitive ou CMP, adopté ou rejeté', () {
      expect(isImportantDecision(_decision()), isTrue);
      expect(
        isImportantDecision(
          _decision(stage: definitiveLectureStage, result: VoteResult.rejete),
        ),
        isTrue,
      );
      expect(
        isImportantDecision(
          _decision(
            type: DecisionType.rejetPrealable,
            result: VoteResult.rejete,
            stage: 'Motion de rejet préalable, $cmpStage',
          ),
        ),
        isTrue,
      );
    });

    test('autres lectures en scrutin ordinaire : non', () {
      for (final stage in [
        "1re lecture à l'AN",
        "Nouvelle lecture à l'AN",
        "Vote sur l'ensemble du texte",
        null,
      ]) {
        expect(
          isImportantDecision(_decision(stage: stage)),
          isFalse,
          reason: '$stage',
        );
      }
    });

    test('jamais : main levée, résolution, décision provisoire', () {
      expect(
        isImportantDecision(_decision(voteMode: VoteMode.mainLevee)),
        isFalse,
      );
      expect(
        isImportantDecision(
          _decision(
            type: DecisionType.resolution,
            stage: 'Résolution (sans valeur de loi)',
            solennel: true,
          ),
        ),
        isFalse,
      );
      expect(
        isImportantDecision(
          _decision(status: DecisionStatus.provisoire, solennel: true),
        ),
        isFalse,
      );
    });
  });
}
