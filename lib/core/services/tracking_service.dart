import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:transify_app/core/network/api_service.dart';

class TrackingService {
  static final TrackingService _instance = TrackingService._internal();
  factory TrackingService() => _instance;
  TrackingService._internal();

  static String? lastError;

  final ApiService _api = ApiService();
  StreamSubscription<Position>? _positionSub;
  String? _activeLoadId;
  String? _activeDriverId;
  String? _activeOwnerId;
  bool _isServiceRunning = false;
  DateTime? _lastUpdateSent;

  bool get isRunning => _isServiceRunning;
  String? get activeLoadId => _activeLoadId;

  /// Check shared preferences on startup to auto-resume active trip tracking
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _activeLoadId = prefs.getString('tracking_load_id');
      _activeDriverId = prefs.getString('tracking_driver_id');
      _activeOwnerId = prefs.getString('tracking_owner_id');

      if (_activeLoadId != null && _activeDriverId != null) {
        debugPrint('[TRACKING-SERVICE] Resuming tracking for load $_activeLoadId after app restart');
        await resumeTracking();
      }
    } catch (e) {
      debugPrint('[TRACKING-SERVICE-ERROR] Initialization failed: $e');
    }
  }

  /// Check location permissions with separate foreground & background requests
  Future<bool> checkAndRequestPermissions() async {
    lastError = null;
    LocationPermission permission;

    // 1. Check current location permission status
    permission = await Geolocator.checkPermission();
    debugPrint('[TRACKING-SERVICE-DEBUG] Initial permission check status: $permission');

    // 2. Request foreground location permission first if currently denied
    if (permission == LocationPermission.denied) {
      debugPrint('[TRACKING-SERVICE] Location permission is denied. Requesting foreground location permission...');
      permission = await Geolocator.requestPermission();
      debugPrint('[TRACKING-SERVICE-DEBUG] Foreground permission request result: $permission');
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('[TRACKING-SERVICE-ERROR] Location permission is permanently denied (deniedForever).');
      lastError = "Location permissions are permanently denied. Please enable them in TransifyGo app settings.";
      
      final serviceEnabledLog = await Geolocator.isLocationServiceEnabled();
      debugPrint('[TRACKING-SERVICE-ERROR] checkAndRequestPermissions failed:');
      debugPrint('  - Current Permission: $permission');
      debugPrint('  - Location Service Enabled: $serviceEnabledLog');
      debugPrint('  - Last Error set: $lastError');
      return false;
    }

    if (permission == LocationPermission.denied) {
      debugPrint('[TRACKING-SERVICE-ERROR] Foreground location permission was denied by the user.');
      lastError = "Location permission is required to start and track active trips.";
      
      final serviceEnabledLog = await Geolocator.isLocationServiceEnabled();
      debugPrint('[TRACKING-SERVICE-ERROR] checkAndRequestPermissions failed:');
      debugPrint('  - Current Permission: $permission');
      debugPrint('  - Location Service Enabled: $serviceEnabledLog');
      debugPrint('  - Last Error set: $lastError');
      return false;
    }

    // 3. Check if location services are enabled on the device (now done after ensuring foreground permission is granted)
    bool serviceEnabled = false;
    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      debugPrint('[TRACKING-SERVICE-DEBUG] Location services enabled check: $serviceEnabled');
    } catch (e) {
      debugPrint('[TRACKING-SERVICE-ERROR] Exception checking location services status: $e');
    }

    if (!serviceEnabled) {
      debugPrint('[TRACKING-SERVICE-WARNING] isLocationServiceEnabled returned false. Verifying with a quick position check to avoid stale cached state...');
      try {
        // Try getting a quick low-accuracy position with a short timeout.
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 2),
          ),
        );
        serviceEnabled = true;
        debugPrint('[TRACKING-SERVICE-DEBUG] Position check succeeded. GPS is actually ON.');
      } on LocationServiceDisabledException {
        serviceEnabled = false;
        debugPrint('[TRACKING-SERVICE-DEBUG] Position check threw LocationServiceDisabledException. GPS is truly OFF.');
      } catch (e) {
        serviceEnabled = true;
        debugPrint('[TRACKING-SERVICE-DEBUG] Position check threw other exception: $e. GPS is assumed ON.');
      }
    }

    if (!serviceEnabled) {
      debugPrint('[TRACKING-SERVICE-ERROR] Location services are disabled on device. Opening settings...');
      lastError = "Location services (GPS) are disabled on your device. Please turn on GPS in your device settings.";
      
      try {
        await Geolocator.openLocationSettings();
      } catch (settingsErr) {
        debugPrint('[TRACKING-SERVICE-ERROR] Failed to open location settings: $settingsErr');
      }

      debugPrint('[TRACKING-SERVICE-ERROR] checkAndRequestPermissions failed:');
      debugPrint('  - Current Permission: $permission');
      debugPrint('  - Location Service Enabled: $serviceEnabled');
      debugPrint('  - Last Error set: $lastError');
      return false;
    }

    // 4. Request background location permission separately on Android 10+ (API 29+)
    if (permission == LocationPermission.whileInUse) {
      debugPrint('[TRACKING-SERVICE] Foreground permission granted. Requesting background location permission separately...');
      try {
        permission = await Geolocator.requestPermission();
        debugPrint('[TRACKING-SERVICE-DEBUG] Separate background permission request result: $permission');
        
        if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
          permission = await Geolocator.checkPermission();
          debugPrint('[TRACKING-SERVICE-DEBUG] Re-checked permission after background request: $permission');
        }
      } catch (e) {
        debugPrint('[TRACKING-SERVICE-ERROR] Separate background permission request encountered error: $e');
      }
    }

    // 5. Fallback: If background permission is denied/not granted but we still have foreground permission (whileInUse),
    // we can still run tracking as a Foreground Service. So we return true!
    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      debugPrint('[TRACKING-SERVICE-DEBUG] Final permission check PASSED with: $permission');
      return true;
    }

    debugPrint('[TRACKING-SERVICE-ERROR] Permission check failed. Final permission status: $permission');
    lastError = "Failed to start tracking due to insufficient location permissions (Current: $permission).";
    
    final serviceEnabledLog = await Geolocator.isLocationServiceEnabled();
    debugPrint('[TRACKING-SERVICE-ERROR] checkAndRequestPermissions failed:');
    debugPrint('  - Current Permission: $permission');
    debugPrint('  - Location Service Enabled: $serviceEnabledLog');
    debugPrint('  - Last Error set: $lastError');
    return false;
  }

  /// Start a new tracking session
  Future<bool> startTracking(String loadId, String driverId, String ownerId) async {
    debugPrint('[TRACKING-SERVICE] Attempting to start tracking for load: $loadId, driver: $driverId, owner: $ownerId');
    lastError = null;
    
    if (_isServiceRunning) {
      if (_activeLoadId == loadId) {
        debugPrint('[TRACKING-SERVICE] Tracking session is already running for this load.');
        return true;
      }
      debugPrint('[TRACKING-SERVICE] Another tracking session is running. Stopping active load: $_activeLoadId');
      await stopTracking(_activeLoadId!);
    }

    // Run permission and location services verification
    final hasPermission = await checkAndRequestPermissions();
    if (!hasPermission) {
      debugPrint('[TRACKING-SERVICE-ERROR] Permission/service check failed. Cannot start trip tracking.');
      return false;
    }

    _activeLoadId = loadId;
    _activeDriverId = driverId;
    _activeOwnerId = ownerId;

    try {
      // 1. Save state in SharedPreferences
      debugPrint('[TRACKING-SERVICE] Saving tracking state in SharedPreferences...');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tracking_load_id', loadId);
      await prefs.setString('tracking_driver_id', driverId);
      await prefs.setString('tracking_owner_id', ownerId);

      // 2. Fetch single current position to verify configuration and GPS status
      debugPrint('[TRACKING-SERVICE] Performing fallback test to retrieve current position...');
      Position initialPos;
      try {
        initialPos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            timeLimit: Duration(seconds: 15),
          ),
        );
        debugPrint('[TRACKING-SERVICE-DEBUG] Current position retrieved successfully: ${initialPos.latitude}, ${initialPos.longitude}');
      } catch (locationErr) {
        debugPrint('[TRACKING-SERVICE-WARNING] Geolocator.getCurrentPosition failed: $locationErr. Trying last known position...');
        
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          initialPos = lastKnown;
          debugPrint('[TRACKING-SERVICE-DEBUG] Fallback to Last Known Position succeeded: ${initialPos.latitude}, ${initialPos.longitude}');
        } else {
          debugPrint('[TRACKING-SERVICE-ERROR] Both getCurrentPosition and getLastKnownPosition failed.');
          if (locationErr is LocationServiceDisabledException) {
            lastError = "Location services (GPS) are disabled on your device. Please turn on GPS in your device settings.";
            try {
              await Geolocator.openLocationSettings();
            } catch (_) {}
          } else if (locationErr is PermissionDeniedException) {
            lastError = "Location permission is denied. Please enable location access for TransifyGo in device settings.";
          } else if (locationErr.toString().toLowerCase().contains('timeout') || locationErr is TimeoutException) {
            lastError = "GPS signal timeout. Please make sure you are in an open area with a clear view of the sky.";
          } else {
            lastError = "Could not fetch GPS coordinates. Please ensure location services are enabled. (Error: $locationErr)";
          }
          rethrow;
        }
      }

      // 3. Write/upsert directly to Firestore to guarantee immediate activation on owner/admin dashboard
      debugPrint('[TRACKING-SERVICE] Initializing Firestore activeTrips document...');
      try {
        await FirebaseFirestore.instance.collection('activeTrips').doc(loadId).set({
          'tripId': loadId,
          'driverId': driverId,
          'ownerId': ownerId,
          'currentLocation': GeoPoint(initialPos.latitude, initialPos.longitude),
          'status': 'started',
          'startedAt': FieldValue.serverTimestamp(),
          'eta': 'Calculating...',
          'distance': '--',
          'lastUpdated': FieldValue.serverTimestamp(),
          'heading': initialPos.heading,
          'speed': initialPos.speed,
        }, SetOptions(merge: true));
        debugPrint('[TRACKING-SERVICE] Firestore activeTrips document successfully created!');
      } catch (firestoreErr) {
        debugPrint('[TRACKING-SERVICE-ERROR] Failed to write start status to Firestore: $firestoreErr');
      }

      // 4. Call backend /start endpoint asynchronously with background fallback to ignore server drops/sleep cold-starts
      debugPrint('[TRACKING-SERVICE] Posting start tracking details to backend...');
      _api.post('/tracking/start', {
        'loadId': loadId,
        'driverId': driverId,
        'ownerId': ownerId,
        'latitude': initialPos.latitude,
        'longitude': initialPos.longitude,
      }).then((response) {
        debugPrint('[TRACKING-SERVICE-DEBUG] Backend response status: ${response.statusCode}, payload: ${response.data}');
      }).catchError((apiErr) {
        debugPrint('[TRACKING-SERVICE-WARNING] Backend startup call failed: $apiErr (silently continuing with direct Firestore sync)');
      });

      _lastUpdateSent = DateTime.now();

      // 5. Start location stream (as Foreground Service with notification)
      debugPrint('[TRACKING-SERVICE] Starting position stream foreground service...');
      _startPositionStream();
      _isServiceRunning = true;
      debugPrint('[TRACKING-SERVICE] Trip tracking successfully started!');
      return true;
    } catch (e) {
      debugPrint('[TRACKING-SERVICE-ERROR] Exception caught in startTracking: $e');
      lastError ??= "Failed to start trip tracking due to an unexpected error. (Error: $e)";
      _clearLocalState();
      return false;
    }
  }

  /// Resume tracking session from state
  Future<void> resumeTracking() async {
    if (_activeLoadId == null || _activeDriverId == null) return;
    final hasPermission = await checkAndRequestPermissions();
    if (!hasPermission) return;

    _startPositionStream();
    _isServiceRunning = true;
  }

  /// Stop current tracking session
  Future<void> stopTracking(String loadId) async {
    if (_activeLoadId != loadId) return;

    debugPrint('[TRACKING-SERVICE] Stopping tracking session for load $loadId');
    try {
      // 1. Cancel location listener
      await _positionSub?.cancel();
      _positionSub = null;

      // 2. Update Firestore status to 'completed'
      try {
        await FirebaseFirestore.instance.collection('activeTrips').doc(loadId).set({
          'status': 'completed',
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('[TRACKING-SERVICE] Firestore status set to completed.');
      } catch (fsErr) {
        debugPrint('[TRACKING-SERVICE-ERROR] Failed to update stop status in Firestore: $fsErr');
      }

      // 3. Alert backend /stop endpoint
      await _api.post('/tracking/stop', { 'loadId': loadId });
    } catch (e) {
      debugPrint('[TRACKING-SERVICE-ERROR] Failed to stop tracking in backend: $e');
    } finally {
      // 4. Clear storage and local status regardless of API outcome
      await _clearLocalState();
    }
  }

  void _startPositionStream() {
    _positionSub?.cancel();

    LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5, // Update more continuously (5 meters instead of 15)
        intervalDuration: const Duration(seconds: 5), // Polling every 5s for smoother realtime tracking
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "TransifyGo is tracking your location for this active trip.",
          notificationTitle: "Trip Tracking Active",
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      );
    }

    _positionSub = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
      _handleLocationUpdate(position);
    }, onError: (error) {
      debugPrint('[TRACKING-SERVICE-ERROR] Stream error: $error');
    });
  }

  Future<void> _handleLocationUpdate(Position position) async {
    if (_activeLoadId == null) return;

    final now = DateTime.now();
    // Throttling: update Firestore at most every 5 seconds for smooth performance
    if (_lastUpdateSent != null && now.difference(_lastUpdateSent!).inSeconds < 5) {
      return;
    }

    // 1. Write to Firestore immediately to bypass any REST backend server wake lock / cold start
    try {
      await FirebaseFirestore.instance.collection('activeTrips').doc(_activeLoadId).set({
        'currentLocation': GeoPoint(position.latitude, position.longitude),
        'status': 'moving',
        'lastUpdated': FieldValue.serverTimestamp(),
        'heading': position.heading,
        'speed': position.speed,
      }, SetOptions(merge: true));
      debugPrint('[TRACKING-SERVICE] Realtime Firestore position sync successful.');
    } catch (fsErr) {
      debugPrint('[TRACKING-SERVICE-ERROR] Realtime Firestore position sync failed: $fsErr');
    }

    // 2. Asynchronously sync backend MongoDB to keep logs updated (throttling backend calls slightly at 10s to prevent spam)
    if (_lastUpdateSent == null || now.difference(_lastUpdateSent!).inSeconds >= 10) {
      _api.post('/tracking/update', {
        'loadId': _activeLoadId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'heading': position.heading,
        'speed': position.speed,
        'timestamp': position.timestamp.toIso8601String(),
      }).then((_) {
        debugPrint('[TRACKING-SERVICE] Backend MongoDB coordinate logger sync successful.');
      }).catchError((backendErr) {
        debugPrint('[TRACKING-SERVICE] Backend MongoDB coordinate sync error: $backendErr (continuing with Firestore)');
      });
      _lastUpdateSent = now;
    }
  }

  Future<void> _clearLocalState() async {
    _activeLoadId = null;
    _activeDriverId = null;
    _activeOwnerId = null;
    _isServiceRunning = false;
    _lastUpdateSent = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('tracking_load_id');
    await prefs.remove('tracking_driver_id');
    await prefs.remove('tracking_owner_id');
  }
}
