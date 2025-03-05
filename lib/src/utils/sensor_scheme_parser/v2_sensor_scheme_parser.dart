import 'dart:typed_data';

import 'sensor_scheme_parser.dart';

class V2SensorSchemeParser extends SensorSchemeParser {
  @override
  List<SensorScheme> parse(List<int> byteStream) {
    int currentIndex = 0;

    int numSensors = byteStream[currentIndex++];
    List<SensorScheme> sensorSchemes = [];
    for (int i = 0; i < numSensors; i++) {
      int sensorId = byteStream[currentIndex++];

      int nameLength = byteStream[currentIndex++];

      List<int> nameBytes =
          byteStream.sublist(currentIndex, currentIndex + nameLength);
      String sensorName = String.fromCharCodes(nameBytes);
      currentIndex += nameLength;

      int componentCount = byteStream[currentIndex++];

      SensorScheme sensorScheme =
          SensorScheme(sensorId, sensorName, componentCount, null);

      for (int j = 0; j < componentCount; j++) {
        int componentType = byteStream[currentIndex++];

        int groupNameLength = byteStream[currentIndex++];

        List<int> groupNameBytes =
            byteStream.sublist(currentIndex, currentIndex + groupNameLength);
        String groupName = String.fromCharCodes(groupNameBytes);
        currentIndex += groupNameLength;

        int componentNameLength = byteStream[currentIndex++];

        List<int> componentNameBytes = byteStream.sublist(
          currentIndex,
          currentIndex + componentNameLength,
        );
        String componentName = String.fromCharCodes(componentNameBytes);
        currentIndex += componentNameLength;

        int unitNameLength = byteStream[currentIndex++];

        List<int> unitNameBytes =
            byteStream.sublist(currentIndex, currentIndex + unitNameLength);
        String unitName = String.fromCharCodes(unitNameBytes);
        currentIndex += unitNameLength;

        Component component =
            Component(componentType, groupName, componentName, unitName);
        sensorScheme.components.add(component);
      }

      //Parse config options
      int availableFeatures = byteStream[currentIndex++];
      List<SensorConfigFeatures> features = [];
      for (SensorConfigFeatures f in SensorConfigFeatures.values) {
        if (availableFeatures & f.value == f.value) {
          features.add(f);
        }
      }

      SensorConfigFrequencies? frequencies;
      if (features.contains(SensorConfigFeatures.frequencyDefinition)) {
        int frequencyCount = byteStream[currentIndex++];
        int defaultFreqIndex = byteStream[currentIndex++];
        int maxStreamingFreqIndex = byteStream[currentIndex++];
        List<int> frequenciesBytes = byteStream.sublist(
          currentIndex,
          currentIndex + frequencyCount * 4,
        );
        List<double> freqs = [];
        for (int k = 0; k < frequencyCount; k++) {
          ByteData byteData = ByteData.sublistView(
            Uint8List.fromList(frequenciesBytes.sublist(k * 4, (k + 1) * 4)),
          );
          freqs.add(byteData.getFloat32(0, Endian.little));
        }
        currentIndex += frequencyCount * 4;
        frequencies = SensorConfigFrequencies(maxStreamingFreqIndex, defaultFreqIndex, freqs);
      }
      sensorScheme.options = SensorConfigOptions(features, frequencies);

      sensorSchemes.add(sensorScheme);
    }

    return sensorSchemes;
  }
}
