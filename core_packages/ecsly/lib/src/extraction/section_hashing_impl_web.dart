const int fnvOffset = 0x811C9DC5;
const int fnvPrime = 0x01000193;
const int _u32Mask = 0xFFFFFFFF;

int mix(final int hash, final int value) {
  final input = (hash ^ value) & _u32Mask;
  final mixed = _mul32(input, fnvPrime);
  return mixed & _u32Mask;
}

int _mul32(final int a, final int b) {
  final aLo = a & 0xFFFF;
  final aHi = (a >> 16) & 0xFFFF;
  final bLo = b & 0xFFFF;
  final bHi = (b >> 16) & 0xFFFF;

  final low = aLo * bLo;
  final mid = ((aHi * bLo) + (aLo * bHi)) & 0xFFFF;
  return (low + (mid << 16)) & _u32Mask;
}
