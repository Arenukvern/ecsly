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
}
