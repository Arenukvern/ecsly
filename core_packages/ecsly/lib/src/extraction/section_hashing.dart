import 'dart:typed_data';

import 'section_hashing_impl_native.dart'
    if (dart.library.js_interop) 'section_hashing_impl_web.dart'
    as impl;

/// Shared deterministic hashing helpers for extract packets/sections.
final class DeterministicSectionHashing {
  DeterministicSectionHashing._();

  static int get fnv64Offset => impl.fnvOffset;
  static int get fnv64Prime => impl.fnvPrime;

  static int mixInt64(final int hash, final int value) => impl.mix(hash, value);

  static int hashInt32Section(final Int32List data, final int count) {
    var hash = fnv64Offset;
    for (var i = 0; i < count; i++) {
      hash = mixInt64(hash, data[i]);
    }
    return hash;
  }

  static int hashUint32Section(final Uint32List data, final int count) {
    var hash = fnv64Offset;
    for (var i = 0; i < count; i++) {
      hash = mixInt64(hash, data[i]);
    }
    return hash;
  }

  static int hashFloat32Section(final Float32List data, final int count) {
    var hash = fnv64Offset;
    final bits = ByteData(4);
    for (var i = 0; i < count; i++) {
      bits.setFloat32(0, data[i], Endian.little);
      hash = mixInt64(hash, bits.getUint32(0, Endian.little));
    }
    return hash;
  }

  /// FNV-1a 32-bit over the UTF-16 code units of [text], each unit mixed
  /// low byte first.
  ///
  /// Every arithmetic step stays under 2^32, so the value is identical on
  /// native, VM and web — unlike the 64-bit section hashes above, which
  /// differ on web because JS rounds integers past 2^53. Use this for
  /// identity that must survive a process, a store or a platform boundary
  /// (cross-consumer payload contracts); keep the 64-bit variants for
  /// in-process extraction equality.
  static int stableStringHash(final String text) {
    var hash = stableOffsetBasis;
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      hash = _stableMix(hash, unit & 0xFF);
      hash = _stableMix(hash, (unit >> 8) & 0xFF);
    }
    return hash;
  }

  /// The offset basis of [stableStringHash]: the FNV-1a 32-bit prime
  /// multiplies it, exposed so implementations can pin the exact recipe.
  static const int stableOffsetBasis = 0x811C9DC5;

  /// The FNV-1a 32-bit prime used by [stableStringHash].
  static const int stablePrime = 0x01000193;

  static int _stableMix(final int hash, final int byte) =>
      ((hash ^ byte) * stablePrime) & 0xFFFFFFFF;
}
