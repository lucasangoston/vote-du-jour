import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Clé privée RSA, lue dans un PEM PKCS#8 (`BEGIN PRIVATE KEY`, format des
/// comptes de service Google) ou PKCS#1 (`BEGIN RSA PRIVATE KEY`).
///
/// Juste assez pour signer un JWT RS256 (RSASSA-PKCS1-v1_5 avec SHA-256),
/// sans autre dépendance cryptographique que `crypto`.
class RsaPrivateKey {
  const RsaPrivateKey({required this.modulus, required this.privateExponent});

  final BigInt modulus;
  final BigInt privateExponent;

  /// Lit une clé PEM ; lève [FormatException] si elle est illisible.
  factory RsaPrivateKey.fromPem(String pem) {
    final match = RegExp(
      r'-----BEGIN (RSA )?PRIVATE KEY-----([\s\S]*?)'
      r'-----END (?:RSA )?PRIVATE KEY-----',
    ).firstMatch(pem);
    if (match == null) {
      throw const FormatException('Clé privée : bloc PEM introuvable');
    }
    final der = base64.decode(match.group(2)!.replaceAll(RegExp(r'\s'), ''));
    var reader = _DerReader(der);
    if (match.group(1) == null) {
      // PKCS#8 : SEQUENCE { version, algorithme, OCTET STRING (PKCS#1) }.
      final info = reader.sequence();
      info.integer();
      info.sequence();
      reader = _DerReader(info.octetString());
    }
    // PKCS#1 : SEQUENCE { version, n, e, d, p, q, dp, dq, qinv }.
    final key = reader.sequence();
    key.integer();
    final n = key.integer();
    key.integer();
    final d = key.integer();
    return RsaPrivateKey(modulus: n, privateExponent: d);
  }

  /// Signature RSASSA-PKCS1-v1_5 / SHA-256 de [message] (RFC 8017, 8.2.1).
  Uint8List signSha256(List<int> message) {
    final k = (modulus.bitLength + 7) ~/ 8;
    final t = [..._sha256DigestInfoPrefix, ...sha256.convert(message).bytes];
    if (k < t.length + 11) {
      throw StateError('Clé RSA trop courte pour SHA-256');
    }
    final em = Uint8List(k)
      ..[1] = 0x01
      ..fillRange(2, k - t.length - 1, 0xff)
      ..setRange(k - t.length, k, t);
    final s = _toBigInt(em).modPow(privateExponent, modulus);
    return _toBytes(s, k);
  }
}

/// Préfixe DER du DigestInfo SHA-256 (RFC 8017, 9.2, note 1).
const _sha256DigestInfoPrefix = [
  0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, //
  0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
];

BigInt _toBigInt(List<int> bytes) {
  var result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b);
  }
  return result;
}

Uint8List _toBytes(BigInt value, int length) {
  final out = Uint8List(length);
  var v = value;
  final mask = BigInt.from(0xff);
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (v & mask).toInt();
    v = v >> 8;
  }
  return out;
}

/// Lecteur DER minimal : SEQUENCE, INTEGER, OCTET STRING.
class _DerReader {
  _DerReader(this._bytes);

  final List<int> _bytes;
  var _pos = 0;

  List<int> _read(int tag) {
    if (_pos + 2 > _bytes.length || _bytes[_pos] != tag) {
      throw const FormatException('Clé privée : structure DER inattendue');
    }
    _pos++;
    var length = _bytes[_pos++];
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      if (count == 0 || count > 4 || _pos + count > _bytes.length) {
        throw const FormatException('Clé privée : longueur DER invalide');
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | _bytes[_pos++];
      }
    }
    if (_pos + length > _bytes.length) {
      throw const FormatException('Clé privée : DER tronqué');
    }
    final content = _bytes.sublist(_pos, _pos + length);
    _pos += length;
    return content;
  }

  _DerReader sequence() => _DerReader(_read(0x30));
  BigInt integer() => _toBigInt(_read(0x02));
  List<int> octetString() => _read(0x04);
}

/// Encodage base64url sans remplissage (JWT, RFC 7515).
String base64UrlNoPad(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// JWT signé en RS256 : `en-tête.charge.signature`.
String signJwtRs256({
  required Map<String, Object?> claims,
  required RsaPrivateKey key,
  String? keyId,
}) {
  final header = {'alg': 'RS256', 'typ': 'JWT', 'kid': ?keyId};
  final signingInput =
      '${base64UrlNoPad(utf8.encode(jsonEncode(header)))}'
      '.${base64UrlNoPad(utf8.encode(jsonEncode(claims)))}';
  final signature = key.signSha256(ascii.encode(signingInput));
  return '$signingInput.${base64UrlNoPad(signature)}';
}
