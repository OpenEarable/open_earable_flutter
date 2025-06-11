import 'dart:convert';
import 'package:http/http.dart' as http;

import '../model/firmware_update_request.dart';

class FirmwareImageRepository {
  Future<List<RemoteFirmware>> getFirmwareImages() async {
    final response = await http.get(
      Uri.parse(
        'https://api.github.com/repos/OpenEarable/open-earable-2/releases/latest',
      ),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch release data');
    }

    final release = jsonDecode(response.body);
    final assets = release['assets'] as List;

    final version = release['tag_name'];
    return assets
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
    }).toList();
  }
}
