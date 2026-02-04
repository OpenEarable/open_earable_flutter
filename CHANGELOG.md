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