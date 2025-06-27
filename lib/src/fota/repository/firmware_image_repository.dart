import 'dart:convert';
import 'package:http/http.dart' as http;

import '../model/firmware_update_request.dart';

class FirmwareImageRepository {
  Future<List<RemoteFirmware>> getFirmwareImages() async {
    final response = await http.get(
      Uri.parse(
        'https://api.github.com/repos/OpenEarable/open-earable-2/releases',
      ),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch release data');
    }

    final releases = jsonDecode(response.body);
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
