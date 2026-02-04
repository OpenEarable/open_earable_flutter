import 'dart:convert';
import 'package:http/http.dart' as http;

import '../model/firmware_update_request.dart';

class BetaFirmwareImageRepository {
  static const _org = 'OpenEarable';
  static const _repo = 'open-earable-2';
  static const _prereleaseTag = 'pr-builds';

  Future<List<RemoteFirmware>> getFirmwareImages() async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://api.github.com/repos/$_org/$_repo/releases/tags/$_prereleaseTag',
        ),
        headers: const {
          'Accept': 'application/vnd.github.v3+json',
        },
      );

      if (response.statusCode != 200) {
        return [];
      }

      final releaseJson = jsonDecode(response.body) as Map<String, dynamic>;

      final assets =
          (releaseJson['assets'] as List<dynamic>).cast<Map<String, dynamic>>();

      final fotaAssets = assets.where((asset) {
        final name = asset['name'] as String? ?? '';
        return name.endsWith('fota.zip');
      });

      final Map<int, Map<String, dynamic>> prMap = {};

      for (final asset in fotaAssets) {
        final name = asset['name'] as String;
        final match = RegExp(
          r'^pr-(\d+)-(.+?)-openearable_v2_fota\.zip$',
        ).firstMatch(name);

        if (match != null) {
          final prNumber = int.parse(match.group(1)!);
          final title = match.group(2)!.replaceAll('_', ' ');

          prMap[prNumber] = {
            'asset': asset,
            'title': title,
          };
        }
      }

      final result = prMap.entries.map((entry) {
        final prNumber = entry.key;
        final asset = entry.value['asset'] as Map<String, dynamic>;
        final title = entry.value['title'] as String;

        return RemoteFirmware(
          name: title,
          version: 'PR #$prNumber',
          url: asset['browser_download_url'] as String,
          type: FirmwareType.multiImage,
        );
      }).toList();

      result.sort((a, b) {
        final aNum =
            int.tryParse(a.version.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
        final bNum =
            int.tryParse(b.version.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
        return bNum.compareTo(aNum);
      });

      return result;
    } catch (e) {
      print('Error fetching beta firmwares: $e');
      return [];
    }
  }
}
