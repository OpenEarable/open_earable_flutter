## Unreleased

* BREAKING CHANGE: `BleGattManager.subscribe` now returns `Future<Stream<List<int>>>`, so callers must `await` subscription setup before listening to BLE notifications.
* BREAKING CHANGE: `SensorHandler.subscribeToSensorData` now returns `Future<Stream<Map<String, dynamic>>>`, so callers must `await` sensor notification readiness before listening to sensor data.
* fixed BLE notification setup races by ensuring subscription futures complete only after the underlying GATT notification subscription is enabled.
* fixed OpenEarable V2 sensor scheme loading on devices that update the scheme characteristic without sending a notification.
* improved OpenEarable V2 sensor scheme loading reliability by keeping one notification subscription active while reading schemes and falling back to synchronous reads.
* fixed race conditions in BLE unsubscribe, duplicate device connection, and stream cancellation handling.

## 2.3.10

* added dynamic power saving mode capability for OpenEarable v2 devices

## 2.3.9

* fixed permissions on web, where web was not able to access the devices BLE services

## 2.3.8

* updated dependencies to latest versions

## 2.3.7

* added erase firmware image slot function for FOTA slot info capability

## 2.3.6

* added function to get all connected system devices
* fixed some issues with bluetooth handling

## 2.3.5

* added FOTA capabilities for wearables to support capability-based firmware updates
* added support for aborting an in-progress FOTA update
* expanded FOTA documentation and API doc comments, including abort flow examples

## 2.3.4

* fixed a bug where the stream of sensor values would not be properly closed when the device is disconnected, which could lead to memory leaks and other issues
* fixed a bug where ble subscriptions whould be cancelled for all devices when a single connection changes
* added methods to handle wearable factories
    * remove wearable factory
    * get all registered wearable factories
    * clear all registered wearable factories

## 2.3.3

* renamed TauRing to OpenRing
* added support for OpenRing temperature sensors (`temp0`, `temp1`, `temp2`) as one 3-channel `Temperature` sensor (`°C`) with software-only on/off control
* Added support for device images with stereo support to display an image for a group of devices

## 2.3.2

* fixed some bugs with Esense devices
    * renamed IMU sensor of Esense to "6-axis IMU" to properly reflect the sensor values that are provided by the device
    * fixed timestamps of Esense sensor values being incorrect
    * assign off value for Esense IMU sensor

## 2.3.1

* added Beta firmware support for OpenEarable v2 devices

## 2.3.0

* BREAKING CHANGE: introduced new capability system
    * deprecated old way of checking capabilities using `is <Capability>`
    * updated documentation to reflect new capability system
* introduced exceptions when conneting to devices fails
* Only support time syncing in OpenEarable v2 devices when the device firmware supports it

## 2.2.6

* fixed some issues with the auto-reconnect logic
* introduced time sync capability
* implemented time sync for OpenEarable v2 devices

## 2.2.5

* added related sensor configuration to esense sensors

## 2.2.4

* added support for IMU of Tau-Ring
* added support for IMU of eSense

## 2.2.3

* marked logger for internal use only
* added function to set logger externally

## 2.2.2

* upgraded dependencies to newest versions

## 2.2.1

* reintroduced support for OpenEarable on Firmware 2.1.*

## 2.2.0

* Fixed a lot of bugs
* added functionality

## 0.1.0

* Create new lib structure
* Support more devices: Polar devices, Cosinuss One, OpenEarable v2

## 0.0.5

README updates (example web app) and add supported platforms. 

## 0.0.4

Extend pipeline to use Flutter.

## 0.0.3

Added compatibility with flutter web.

## 0.0.2

Connecting to earable now retries after first failure.

## 0.0.1

* TODO: Describe initial release.
