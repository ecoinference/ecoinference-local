/// Debug / testing configuration.
///
/// Flip [kUseMockLocation] to `false` (and rebuild) once all location-based
/// tool bugs have been resolved and you want real GPS to be used.
const bool kUseMockLocation = false;

/// Swisher, Iowa USA (zip 52338) — default test location.
const double kMockLatitude = 41.8444;
const double kMockLongitude = -91.6457;

/// UTC offset for the Cedar Rapids / Iowa City area.
///   CDT (Daylight — Mar to Nov) = UTC-5
///   CST (Standard — Nov to Mar) = UTC-6
const double kMockTimezoneOffset = -5.0; // CDT
