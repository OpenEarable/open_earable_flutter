import 'models/devices/open_earable_v2.dart';
import 'models/devices/cosinuss_one.dart';
import 'models/devices/open_earable_v1.dart';
import 'models/devices/polar.dart';

const String sensorServiceUuid = "34c2e3bb-34aa-11eb-adc1-0242ac120002";
const String sensorConfigurationCharacteristicUuid =
    "34c2e3bd-34aa-11eb-adc1-0242ac120002";
const String sensorConfigurationV2CharacteristicUuid =
    "34c2e3be-34aa-11eb-adc1-0242ac120002";
const String sensorDataCharacteristicUuid =
    "34c2e3bc-34aa-11eb-adc1-0242ac120002";

const String deviceInfoServiceUuid = "45622510-6468-465a-b141-0b9b0f96b468";
const String deviceIdentifierCharacteristicUuid =
    "45622511-6468-465a-b141-0b9b0f96b468";
const String deviceFirmwareVersionCharacteristicUuid =
    "45622512-6468-465a-b141-0b9b0f96b468";
const String deviceHardwareVersionCharacteristicUuid =
    "45622513-6468-465a-b141-0b9b0f96b468";

const String parseInfoServiceUuid = "caa25cb7-7e1b-44f2-adc9-e8c06c9ced43";
const String schemeCharacteristicUuid = "caa25cb8-7e1b-44f2-adc9-e8c06c9ced43";
const String sensorListCharacteristicUuid = "caa25cb9-7e1b-44f2-adc9-e8c06c9ced43";
const String requestSensorSchemeCharacteristicUuid =
    "caa25cba-7e1b-44f2-adc9-e8c06c9ced43";
const String sensorSchemeCharacteristicUuid = "caa25cbb-7e1b-44f2-adc9-e8c06c9ced43";

const String audioPlayerServiceUuid = "5669146e-476d-11ee-be56-0242ac120002";
const String audioSourceCharacteristic = "566916a8-476d-11ee-be56-0242ac120002";
const String audioStateCharacteristic = "566916a9-476d-11ee-be56-0242ac120002";

const String batteryServiceUuid = "180F";
const String batteryLevelCharacteristicUuid = "2A19";

const String buttonServiceUuid = "29c10bdc-4773-11ee-be56-0242ac120002";
const String buttonStateCharacteristicUuid =
    "29c10f38-4773-11ee-be56-0242ac120002";

const String ledServiceUuid = "81040a2e-4819-11ee-be56-0242ac120002";
const String ledSetStateCharacteristic = "81040e7a-4819-11ee-be56-0242ac120002";

// All UUIDs in a list for filters
List<String> allServiceUuids = [
  OpenEarableV1.ledServiceUuid,
  OpenEarableV1.deviceInfoServiceUuid,
  OpenEarableV1.audioPlayerServiceUuid,
  OpenEarableV1.sensorServiceUuid,
  OpenEarableV1.parseInfoServiceUuid,
  OpenEarableV1.buttonServiceUuid,
  OpenEarableV1.batteryServiceUuid,

  OpenEarableV2.deviceInfoServiceUuid,
  OpenEarableV2.batteryServiceUuid,
  OpenEarableV2.ledServiceUuid,

  CosinussOne.ppgAndAccServiceUuid,
  CosinussOne.temperatureServiceUuid,
  CosinussOne.heartRateServiceUuid,
  Polar.disServiceUuid,
  Polar.heartRateServiceUuid,
];
