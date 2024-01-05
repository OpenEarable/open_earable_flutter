// Code from https://github.com/nelsonwenner/mobile-sensors-filter-mahony/

import 'dart:math';

class MahonyAHRS {
  //late double _defaultFrequency = 512.0; // (1.0 / 512.0) sample frequency in Hz
  late double _qW; // data quaternion
  late double _qX; // data quaternion
  late double _qY; // data quaternion
  late double _qZ; // data quaternion
  late double _integralFbX; // apply integral feedback
  late double _integralFbY; // apply integral feedback
  late double _integralFbZ; // apply integral feedback
  late double _ki; // 2 * integral gain (Ki), (2.0 * 0.0) = 0.0
  late double _kp; // 2 * proportional gain (Kp), (2.0 * 0.5) = 1.0

  MahonyAHRS() {
    _qW = 1.0;
    _qX = 0.0;
    _qY = 0.0;
    _qZ = 0.0;
    _integralFbX = 0.0;
    _integralFbY = 0.0;
    _integralFbZ = 0.0;
    _kp = 10.0;
    _ki = 0.0;
  }

  List<double> get quaternion => [_qW, _qX, _qY, _qZ];

  void resetValues() {
    _qW = 1.0;
    _qX = 0.0;
    _qY = 0.0;
    _qZ = 0.0;
    _integralFbX = 0.0;
    _integralFbY = 0.0;
    _integralFbZ = 0.0;
    _kp = 1.0;
    _ki = 0.0;
  }

  void update(double ax, double ay, double az, double gx, double gy, double gz,
      double td) {
    double q1 = _qW;
    double q2 = _qX;
    double q3 = _qY;
    double q4 = _qZ;

    double norm;
    double vx, vy, vz;
    double ex, ey, ez;
    double pa, pb, pc;

    // Convert gyroscope degrees/sec to radians/sec, deg2rad
    // PI = 3.141592653589793
    // (PI / 180) = 0.0174533
    gx *= 0.0174533;
    gy *= 0.0174533;
    gz *= 0.0174533;

    // Compute feedback only if accelerometer measurement valid
    // (avoids NaN in accelerometer normalisation)
    if ((!((ax == 0.0) && (ay == 0.0) && (az == 0.0)))) {
      // Normalise accelerometer measurement
      norm = 1.0 / sqrt(ax * ax + ay * ay + az * az);
      ax *= norm;
      ay *= norm;
      az *= norm;

      // Estimated direction of gravity
      vx = 2.0 * (q2 * q4 - q1 * q3);
      vy = 2.0 * (q1 * q2 + q3 * q4);
      vz = q1 * q1 - q2 * q2 - q3 * q3 + q4 * q4;

      // Error is cross product between estimated
      // direction and measured direction of gravity
      ex = (ay * vz - az * vy);
      ey = (az * vx - ax * vz);
      ez = (ax * vy - ay * vx);

      if (_ki > 0.0) {
        _integralFbX += ex; // accumulate integral error
        _integralFbY += ey;
        _integralFbZ += ez;
      } else {
        _integralFbX = 0.0; // prevent integral wind up
        _integralFbY = 0.0;
        _integralFbZ = 0.0;
      }

      // Apply feedback terms
      gx += _kp * ex + _ki * _integralFbX;
      gy += _kp * ey + _ki * _integralFbY;
      gz += _kp * ez + _ki * _integralFbZ;
    }

    // Integrate rate of change of quaternion
    gx *= (0.5 * td); // pre-multiply common factors
    gy *= (0.5 * td);
    gz *= (0.5 * td);
    pa = q2;
    pb = q3;
    pc = q4;
    q1 = q1 + (-q2 * gx - q3 * gy - q4 * gz); // create quaternion
    q2 = pa + (q1 * gx + pb * gz - pc * gy);
    q3 = pb + (q1 * gy - pa * gz + pc * gx);
    q4 = pc + (q1 * gz + pa * gy - pb * gx);

    // Normalise _quaternion
    norm = 1.0 / sqrt(q1 * q1 + q2 * q2 + q3 * q3 + q4 * q4);

    _qW = q1 * norm;
    _qX = q2 * norm;
    _qY = q3 * norm;
    _qZ = q4 * norm;
  }
}
