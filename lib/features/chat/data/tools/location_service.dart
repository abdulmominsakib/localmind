import 'dart:async';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Thin wrapper around [Geolocator] + [Geocoding] for the built-in
/// location tools.
///
/// All methods return plain Dart types (strings / maps) so tool results can
/// be serialised without leaking platform model classes into the tool layer.
///
/// Location is fetched on demand only (no background tracking, no caching,
/// no persistence). Reverse-geocoding is best-effort: when it fails the
/// raw coordinates are still returned with a `geocoding_error` note.
class LocationService {
  LocationService._();
  static final instance = LocationService._();

  final Geocoding _geocoding = Geocoding();

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  /// Request when-in-use location access. Returns `true` when granted.
  Future<bool> requestAccess() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Check current permission status without prompting.
  Future<bool> hasAccess() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  // ---------------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------------

  /// Returns a JSON-friendly map with coordinates and reverse-geocoded place.
  ///
  /// Throws a [StateError] with a human-readable message when location
  /// services are disabled, permission is missing, or the fix times out.
  Future<Map<String, dynamic>> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw StateError(
        'Location services are disabled. '
        'Please enable location services on your device.',
      );
    }

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      throw StateError(
        'Location permission permanently denied. '
        'Please grant location access in your device settings.',
      );
    }
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      throw StateError(
        'Location permission not granted. '
        'Please enable Location Access in Settings.',
      );
    }

    late final Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } on TimeoutException {
      throw StateError(
        'Timed out while getting your location. Please try again.',
      );
    }

    final result = <String, dynamic>{
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy_m': position.accuracy,
      'timestamp': position.timestamp.toIso8601String(),
    };

    try {
      final placemarks = await _geocoding.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final placemark = <String, dynamic>{
          'name': _nullIfEmpty(place.name),
          'street': _nullIfEmpty(place.street),
          'locality': _nullIfEmpty(place.locality),
          'sub_admin_area': _nullIfEmpty(place.subAdministrativeArea),
          'admin_area': _nullIfEmpty(place.administrativeArea),
          'postal_code': _nullIfEmpty(place.postalCode),
          'country': _nullIfEmpty(place.country),
          'iso_country_code': _nullIfEmpty(place.isoCountryCode),
        };
        result['placemark'] = placemark;
        result['formatted_address'] = _formatAddress(place);
      }
    } catch (e) {
      result['geocoding_error'] =
          'Reverse-geocoding unavailable ($e). Coordinates are still valid.';
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String? _nullIfEmpty(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  String _formatAddress(Placemark place) {
    final parts = [
      place.street,
      place.locality,
      place.administrativeArea,
      place.postalCode,
      place.country,
    ].where((p) => p != null && p.trim().isNotEmpty).toList(growable: false);
    return parts.join(', ');
  }
}
