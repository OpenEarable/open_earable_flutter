class ExGPreset {
  final String name;
  final double lowerCutoff;
  final double higherCutoff;
  final int samplingFrequency;
  final int filterOrder;

  ExGPreset({
    required this.name,
    required this.lowerCutoff,
    required this.higherCutoff,
    required this.samplingFrequency,
    required this.filterOrder,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'lowerCutoff': lowerCutoff,
    'higherCutoff': higherCutoff,
    'samplingFrequency': samplingFrequency,
    'filterOrder': filterOrder,
  };

  factory ExGPreset.fromJson(Map<String, dynamic> json) => ExGPreset(
    name: json['name'],
    lowerCutoff: (json['lowerCutoff'] as num).toDouble(),
    higherCutoff: (json['higherCutoff'] as num).toDouble(),
    samplingFrequency: json['samplingFrequency'],
    filterOrder: json['filterOrder'],
  );
}
