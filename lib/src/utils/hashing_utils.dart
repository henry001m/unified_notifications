String deriveStableHash(String value) {
  return value.hashCode.toUnsigned(32).toRadixString(16);
}
