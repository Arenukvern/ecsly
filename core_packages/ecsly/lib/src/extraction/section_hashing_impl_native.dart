// ignore: avoid_js_rounded_ints
const int fnvOffset = 0xcbf29ce484222325;
const int fnvPrime = 0x100000001b3;
const int u64Mask = 0xFFFFFFFFFFFFFFFF;

int mix(final int hash, final int value) {
  final mixed = (hash ^ (value & u64Mask)) * fnvPrime;
  return mixed & u64Mask;
}
