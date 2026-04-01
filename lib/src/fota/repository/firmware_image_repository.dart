import 'dart:convert';
import 'package:http/http.dart' as http;

import '../model/firmware_update_request.dart';

/// Repository for stable firmware releases published from the main GitHub
/// release feed.
class FirmwareImageRepository {
  /// Returns all non-draft, non-prerelease firmware assets from the upstream
  /// OpenEarable release feed.
  Future<List<RemoteFirmware>> getFirmwareImages() async {
    final response = await http.get(
      Uri.parse(
        'https://api.github.com/repos/OpenEarable/open-earable-2/releases',
      ),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch release data');
    }

    final releases = (jsonDecode(response.body) as List)
        .where(
          (release) =>
              release['prerelease'] != true && release['draft'] != true,
        )
        .toList();
    List<RemoteFirmware> firmwares = [];
    for (final release in releases) {
      final assets = release['assets'] as List;

      final version = release['tag_name'];
      final firmware = assets
          .where(
        (asset) =>
            asset['name'].endsWith('.zip') || asset['name'].endsWith('.bin'),
      )
          .map<RemoteFirmware>((asset) {
        final name = asset['name'];
        final url = asset['browser_download_url'];
        final type = name.endsWith('.zip')
            ? FirmwareType.multiImage
            : FirmwareType.singleImage;
        final displayName = name.split('_').first + ' $version';
        return RemoteFirmware(
          name: displayName,
          version: version,
          url: url,
          type: type,
        );
      });
      firmwares.addAll(firmware);
    }
    return firmwares;
  }

  /// Checks whether the newest published stable version is newer than
  /// [currentVersion].
  Future<bool> newerFirmwareVersionAvailable(
    String? currentVersion,
  ) async {
    if (currentVersion == null || currentVersion.isEmpty) {
      return false;
    }
    try {
      final latestVersion = await getLatestFirmwareVersion();
      return isNewerVersion(latestVersion, currentVersion);
    } catch (e) {
      print('Error checking for new firmware version: $e');
      return false;
    }
  }

  /// Returns the newest stable firmware version tag without a leading `v`.
  Future<String> getLatestFirmwareVersion() async {
    final response = await http.get(
      Uri.parse(
        'https://api.github.com/repos/OpenEarable/open-earable-2/releases/latest',
      ),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch latest release');
    }

    final latestRelease = jsonDecode(response.body);
    return (latestRelease['tag_name'] as String).replaceFirst('v', '');
  }

  /// Compares semantic version strings and returns `true` when [latest] is
  /// newer than [current].
  bool isNewerVersion(String latest, String current) {
    List<int> parse(String v) => v.split('.').map(int.parse).toList();
    final latestParts = parse(latest);
    final currentParts = parse(current);

    for (int i = 0; i < latestParts.length; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }
}
