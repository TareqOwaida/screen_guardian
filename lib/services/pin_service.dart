import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Salted SHA-256 hashing for parent / profile PINs. PINs are never stored in
/// plain text.
class PinService {
  static final Random _rng = Random.secure();

  static String newSalt() {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt::$pin')).toString();

  static bool verify(String pin, String? hash, String? salt) {
    if (hash == null || salt == null) return false;
    return PinService.hash(pin, salt) == hash;
  }
}
