import 'package:vote_contract/vote_contract.dart';

/// Un scrutin public tel que publié par l'Assemblée, débarrassé du format
/// officiel (voir `dump_reader.dart`).
class Scrutin {
  const Scrutin({
    required this.uid,
    required this.numero,
    required this.date,
    required this.titre,
    required this.codeTypeVote,
    required this.libelleTypeVote,
    required this.result,
    required this.decompte,
    required this.dossierRef,
    required this.groupVotes,
    this.seanceRef,
  });

  /// Identifiant officiel, par exemple `VTANR5L17V7946`.
  final String uid;

  final int numero;

  /// Jour du scrutin, à minuit UTC (l'open data ne donne pas l'heure).
  final DateTime date;

  /// Intitulé officiel (« l'ensemble du projet de loi… »).
  final String titre;

  /// `SPO` (ordinaire), `SPS` (solennel) ou `MOC` (motion de censure).
  final String codeTypeVote;

  /// « scrutin public ordinaire », « scrutin public solennel » ou
  /// « motion de censure ».
  final String libelleTypeVote;

  final VoteResult result;
  final Decompte decompte;

  /// Référence du dossier législatif (`DLR5L17N…`), absente pour certains
  /// scrutins (motions de censure, résolutions…).
  final String? dossierRef;

  final List<GroupVote> groupVotes;

  /// Séance du vote (`RUANR5L17S2027IDS30951`), la réunion de l'agenda ;
  /// absente sur le site de l'Assemblée.
  final String? seanceRef;
}

/// Décompte des voix.
class Decompte {
  const Decompte({
    required this.pour,
    required this.contre,
    required this.abstentions,
    required this.nonVotants,
  });

  final int pour;
  final int contre;
  final int abstentions;
  final int nonVotants;
}

/// Vote d'un groupe politique.
class GroupVote {
  const GroupVote({
    required this.organeRef,
    required this.positionMajoritaire,
    required this.decompte,
  });

  /// Référence de l'organe (groupe), par exemple `PO845401`.
  final String organeRef;

  /// « pour », « contre », « abstention » ou « nonVotant ».
  final String positionMajoritaire;

  final Decompte decompte;
}
