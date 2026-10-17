/// Conversion UTC <-> heure de Paris sans base de fuseaux horaires : heure
/// d'été du dernier dimanche de mars 01:00 UTC au dernier dimanche d'octobre
/// 01:00 UTC.
library;

DateTime _dernierDimanche(int annee, int mois) {
  var d = DateTime.utc(annee, mois + 1, 0, 1); // dernier jour du mois, 01:00
  while (d.weekday != DateTime.sunday) {
    d = d.subtract(const Duration(days: 1));
  }
  return d;
}

/// Décalage de Paris par rapport à UTC à l'instant [utc].
Duration decalageParis(DateTime utc) {
  final debut = _dernierDimanche(utc.year, 3);
  final fin = _dernierDimanche(utc.year, 10);
  final ete = !utc.isBefore(debut) && utc.isBefore(fin);
  return Duration(hours: ete ? 2 : 1);
}

/// Heure de Paris, représentée comme un DateTime UTC dont les champs sont
/// ceux de l'heure locale (pour l'affichage et le regroupement par heure).
DateTime versParis(DateTime utc) => utc.toUtc().add(decalageParis(utc.toUtc()));

/// Inverse de [versParis] pour une heure locale saisie à la main.
DateTime depuisParis(DateTime local) {
  final naif = DateTime.utc(
    local.year,
    local.month,
    local.day,
    local.hour,
    local.minute,
    local.second,
  );
  final approx = naif.subtract(const Duration(hours: 1));
  return naif.subtract(decalageParis(approx));
}

String formatParis(DateTime utc) {
  final p = versParis(utc);
  String d2(int v) => v.toString().padLeft(2, '0');
  return '${p.year}-${d2(p.month)}-${d2(p.day)} ${d2(p.hour)}:${d2(p.minute)}';
}
