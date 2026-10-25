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
    this.membres,
    this.votants = const [],
  });

  /// Référence de l'organe (groupe), par exemple `PO845401`.
  final String organeRef;

  /// « pour », « contre », « abstention » ou « nonVotant ».
  final String positionMajoritaire;

  final Decompte decompte;

  /// Effectif du groupe le jour du scrutin (`nombreMembresGroupe`), s'il est
  /// donné.
  final int? membres;

  /// Vote nominatif des membres du groupe (`decompteNominatif`, #71) : pour,
  /// contre, abstentions et non-votants ; les absents n'y figurent pas.
  final List<NominalVote> votants;
}

/// Vote nominatif d'un député lors d'un scrutin (#71).
class NominalVote {
  const NominalVote({required this.acteurRef, required this.vote, this.place});

  /// Référence du député (acteur), par exemple `PA793432`.
  final String acteurRef;

  /// Place occupée dans l'hémicycle (`numPlace`), si l'open data la donne.
  final int? place;

  /// [SeatVote.pour], [SeatVote.contre], [SeatVote.abstention] ou
  /// [SeatVote.nonVotant].
  final SeatVote vote;
}
