part of open_earable_flutter;

// Encapsulate left and right earable for OpenEarable V2
class OpenEarableManager {
  final OpenEarable leftEarable;
  final OpenEarable rightEarable;
  OpenEarable? activeOpenEarable;

  OpenEarableManager()
      : leftEarable = OpenEarable(),
        rightEarable = OpenEarable();

  void setActiveEarable(String side) {
    if (side == "left") {
      activeOpenEarable = leftEarable;
    } else if (side == "right") {
      activeOpenEarable = rightEarable;
    }
  }
}
