import 'package:flutter_test/flutter_test.dart';
import 'package:open_earable_flutter/src/fota/repository/firmware_image_repository.dart';

void main() {
  final repository = FirmwareImageRepository();

  test('compares stable release components numerically', () {
    expect(repository.isNewerVersion('2.2.10', '2.2.9'), isTrue);
    expect(repository.isNewerVersion('2.3.0', '2.2.10'), isTrue);
    expect(repository.isNewerVersion('2.2.9', '2.2.9'), isFalse);
    expect(repository.isNewerVersion('2.2.8', '2.2.9'), isFalse);
  });

  test('accepts the development label observed on the earable', () {
    const current = '2.2.9-dev.100+g94986934.dirty';
    expect(repository.isNewerVersion('2.2.8', current), isFalse);
    expect(repository.isNewerVersion('2.2.9', current), isTrue);
    expect(repository.isNewerVersion('2.2.10', current), isTrue);
  });

  test('orders prereleases numerically and below the stable release', () {
    expect(repository.isNewerVersion('2.2.9-dev.10', '2.2.9-dev.9'), isTrue);
    expect(repository.isNewerVersion('2.2.9-pr292', '2.2.9'), isFalse);
    expect(repository.isNewerVersion('2.2.9', '2.2.9-pr292'), isTrue);
  });

  test('ignores hashes and other build metadata', () {
    expect(repository.isNewerVersion('2.2.9+zzz', '2.2.9+aaa'), isFalse);
    expect(
      repository.isNewerVersion('2.2.9-dev.1+gabc', '2.2.9-dev.1+gdef.dirty'),
      isFalse,
    );
  });

  test('accepts release tag prefixes and legacy trailing NUL bytes', () {
    expect(repository.isNewerVersion('v2.2.9', '2.2.8\u0000'), isTrue);
    expect(repository.isNewerVersion(' V2.2.9 ', '2.2.9\u0000'), isFalse);
  });

  test('malformed or incomplete versions do not throw or suggest updates', () {
    for (final label in ['', 'unknown', '2', '2.2.x', 'garbage2.2.9']) {
      expect(repository.isNewerVersion('2.2.9', label), isFalse);
      expect(repository.isNewerVersion(label, '2.2.9'), isFalse);
    }
  });
}
