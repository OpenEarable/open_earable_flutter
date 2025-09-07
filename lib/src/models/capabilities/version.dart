class Version implements Comparable<Version> {
  final List<int> parts;

  Version._(this.parts);

  factory Version.parse(String v) {
    final clean = v.trim();
    if (!RegExp(r'^\d+(\.\d+)*$').hasMatch(clean)) {
      throw FormatException('Invalid version: $v');
    }
    final nums = clean.split('.').map(int.parse).toList();
    // normalize length so 1.2 == 1.2.0
    while (nums.length < 3) {
      nums.add(0);
    }
    return Version._(nums);
  }

  @override
  int compareTo(Version other) {
    final maxLen = (parts.length > other.parts.length) ? parts.length : other.parts.length;
    for (var i = 0; i < maxLen; i++) {
      final a = i < parts.length ? parts[i] : 0;
      final b = i < other.parts.length ? other.parts[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }

  @override
  String toString() => parts.takeWhile((_) => true).join('.');
}

int compareVersions(String a, String b) =>
    Version.parse(a).compareTo(Version.parse(b));

/// Returns the newest `count` versions from the provided list (sorted desc, unique).
List<String> newestN(List<String> allVersions, int count) {
  final uniq = {
    for (final v in allVersions) Version.parse(v).toString(): Version.parse(v)
  }.values.toList();
  uniq.sort((a, b) => b.compareTo(a)); // newest first
  return uniq.take(count).map((v) => v.toString()).toList();
}

/// True if `deviceVersion` is among the newest `count` releases.
bool isFirmwareSupported({
  required String deviceVersion,
  required List<String> releasedVersions,
  required int newestCount,
  bool sameMajorOnly = false, // set true if you only support the latest N within the current major
}) {
  final device = Version.parse(deviceVersion);
  var pool = releasedVersions.map(Version.parse).toList();

  if (sameMajorOnly && pool.isNotEmpty) {
    // Filter to versions with the same major as the newest release
    pool.sort((a, b) => b.compareTo(a));
    final currentMajor = pool.first.parts[0];
    pool = pool.where((v) => v.parts[0] == currentMajor).toList();
  }

  pool.sort((a, b) => b.compareTo(a));
  final supported = pool.take(newestCount).toSet();
  return supported.contains(device);
}