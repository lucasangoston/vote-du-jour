import 'package:vote_contract/vote_contract.dart';

/// Logos des groupes de la 17e législature, embarqués dans l'app et associés
/// par sigle (source et licence de chaque fichier :
/// `assets/group_logos/SOURCES.md`). Un groupe absent (non-inscrits, nouveau
/// groupe) s'affiche en vignette à sigle.
const groupLogoAssets = {
  'RN': 'assets/group_logos/rn.png',
  'EPR': 'assets/group_logos/epr.png',
  'LFI-NFP': 'assets/group_logos/lfi.png',
  'SOC': 'assets/group_logos/soc.png',
  'DR': 'assets/group_logos/dr.png',
  'EcoS': 'assets/group_logos/ecos.png',
  'Dem': 'assets/group_logos/dem.png',
  'HOR': 'assets/group_logos/hor.png',
  'LIOT': 'assets/group_logos/liot.png',
  'GDR': 'assets/group_logos/gdr.png',
  'UDR': 'assets/group_logos/udr.png',
};

/// Logo embarqué du groupe, s'il est connu.
String? groupLogoAsset(GroupVoteDetail group) =>
    groupLogoAssets[group.abbreviation];

/// Texte de la vignette à sigle : le sigle, sinon les initiales du nom.
String groupMark(GroupVoteDetail group) =>
    group.abbreviation ??
    group.name
        .split(RegExp(r"[\s'-]+"))
        .where((word) => word.length > 2)
        .map((word) => word[0].toUpperCase())
        .take(3)
        .join();

/// Légende sous le logo : le sigle ; « Non inscrits » pour les députés sans
/// groupe, dont la vignette porte déjà « NI ».
String groupCaption(GroupVoteDetail group) => switch (group.abbreviation) {
  'NI' => 'Non inscrits',
  final abbreviation? => abbreviation,
  null => group.name,
};
