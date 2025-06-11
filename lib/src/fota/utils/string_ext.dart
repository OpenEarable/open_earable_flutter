extension StringExt on String {
  String replaceIfEmpty(String replacer) {
    return isEmpty ? replacer : this;
  }
}
