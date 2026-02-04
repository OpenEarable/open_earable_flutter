import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_earable_flutter/src/fota/repository/beta_image_repository.dart';

class UnifiedFirmwareRepository {
  final FirmwareImageRepository _stableRepository = FirmwareImageRepository();
  final BetaFirmwareImageRepository _betaRepository =
      BetaFirmwareImageRepository();

  List<FirmwareEntry>? _cachedStable;
  List<FirmwareEntry>? _cachedBeta;
  DateTime? _lastFetchTime;

  static const _cacheDuration = Duration(minutes: 15);

  bool _isCacheExpired() {
    if (_lastFetchTime == null) return true;
    return DateTime.now().difference(_lastFetchTime!) > _cacheDuration;
  }

  Future<List<FirmwareEntry>> getStableFirmwares({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedStable != null && !_isCacheExpired()) {
      return _cachedStable!;
    }

    final firmwares = await _stableRepository.getFirmwareImages();
    _cachedStable = firmwares
        .map(
          (fw) => FirmwareEntry(
            firmware: fw,
            source: FirmwareSource.stable,
          ),
        )
        .toList();

    _lastFetchTime = DateTime.now();
    return _cachedStable!;
  }

  Future<List<FirmwareEntry>> getBetaFirmwares({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedBeta != null && !_isCacheExpired()) {
      return _cachedBeta!;
    }

    final firmwares = await _betaRepository.getFirmwareImages();
    _cachedBeta = firmwares
        .map(
          (fw) => FirmwareEntry(
            firmware: fw,
            source: FirmwareSource.beta,
          ),
        )
        .toList();

    _lastFetchTime = DateTime.now();
    return _cachedBeta!;
  }

  Future<List<FirmwareEntry>> getAllFirmwares({
    bool includeBeta = false,
  }) async {
    final stable = await getStableFirmwares();
    if (!includeBeta) return stable;

    final beta = await getBetaFirmwares();
    return [...stable, ...beta];
  }

  void clearCache() {
    _cachedStable = null;
    _cachedBeta = null;
    _lastFetchTime = null;
  }
}

enum FirmwareSource { stable, beta }

class FirmwareEntry {
  final RemoteFirmware firmware;
  final FirmwareSource source;

  FirmwareEntry({
    required this.firmware,
    required this.source,
  });

  bool get isBeta => source == FirmwareSource.beta;
  bool get isStable => source == FirmwareSource.stable;
}
