import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:transify_app/core/constants/app_colors.dart';
import 'package:transify_app/core/constants/api_keys.dart';
import 'package:transify_app/core/network/api_service.dart';
import 'package:transify_app/core/services/directions_service.dart';

class TrackVehicleScreen extends StatefulWidget {
  final Map<String, dynamic> loadData;

  const TrackVehicleScreen({super.key, required this.loadData});

  @override
  State<TrackVehicleScreen> createState() => _TrackVehicleScreenState();
}

class _TrackVehicleScreenState extends State<TrackVehicleScreen> with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  GoogleMapController? _mapController;
  Timer? _pollingTimer;

  bool _isLoading = true;
  bool _isFirstLoad = true;
  
  // Tracking data from backend
  double? _driverLat;
  double? _driverLng;
  String? _tripStatus;
  DateTime? _lastUpdated;

  // Road stats from Google Distance Matrix / Directions
  String? _roadDistanceText;
  String? _roadDurationText;
  bool _calculatingRoute = false;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  
  // Directions route points
  List<LatLng> polylineCoordinates = [];

  // Resolved coordinates for pickup and drop
  double? _pickupLat;
  double? _pickupLng;
  double? _dropLat;
  double? _dropLng;

  // Custom truck icon
  BitmapDescriptor? _truckIcon;

  // Animation controller for smooth vehicle movement
  AnimationController? _movementController;
  LatLng? _oldDriverPosition;
  LatLng? _targetDriverPosition;
  double _markerRotation = 0.0;

  @override
  void initState() {
    super.initState();
    
    // Movement animation controller setup
    _movementController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _movementController!.addListener(() {
      if (_oldDriverPosition != null && _targetDriverPosition != null) {
        final double t = _movementController!.value;
        final double lat = _oldDriverPosition!.latitude + (_targetDriverPosition!.latitude - _oldDriverPosition!.latitude) * t;
        final double lng = _oldDriverPosition!.longitude + (_targetDriverPosition!.longitude - _oldDriverPosition!.longitude) * t;
        
        setState(() {
          _driverLat = lat;
          _driverLng = lng;
          _updateMapData();
        });
      }
    });

    _loadAssetsAndRoute();
    
    // Poll every 15 seconds
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 15), 
      (_) => _fetchTrackingInfo(quiet: true),
    );
  }

  StreamSubscription<DocumentSnapshot>? _firestoreSub;

  @override
  void dispose() {
    _firestoreSub?.cancel();
    _pollingTimer?.cancel();
    _movementController?.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadAssetsAndRoute() async {
    await _loadCustomMarker();
    await _fetchFullRoute();
    await _fetchTrackingInfo();
    _startFirestoreListener();
  }

  Future<BitmapDescriptor> _getBitmapDescriptorFromAsset(String path, int width) async {
    final byteData = await DefaultAssetBundle.of(context).load(path);
    final ui.Codec codec = await ui.instantiateImageCodec(
      byteData.buffer.asUint8List(),
      targetWidth: width,
    );
    final ui.FrameInfo fi = await codec.getNextFrame();
    final bytes = (await fi.image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    return BitmapDescriptor.bytes(bytes);
  }

  /// Load custom truck marker from assets, fallback to vector-drawn canvas on failure
  Future<void> _loadCustomMarker() async {
    try {
      final icon = await _getBitmapDescriptorFromAsset('assets/images/truck_icon.png', 65);
      if (mounted) {
        setState(() {
          _truckIcon = icon;
        });
      }
    } catch (e) {
      debugPrint('[TRACK-VEHICLE-ERROR] Custom asset marker loading failed, falling back to canvas: $e');
      await _loadCustomMarkerCanvas();
    }
  }

  /// Load vector-drawn truck marker fallback
  Future<void> _loadCustomMarkerCanvas() async {
    try {
      final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(pictureRecorder);
      
      final Paint circlePaint = Paint()..color = AppColors.primaryBlue;
      final Paint borderPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 3.5
        ..style = PaintingStyle.stroke;
        
      // Draw background circle
      canvas.drawCircle(const Offset(40, 40), 28, circlePaint);
      canvas.drawCircle(const Offset(40, 40), 28, borderPaint);
      
      // Draw pointer facing North
      final Paint arrowPaint = Paint()..color = Colors.white;
      final Path path = Path();
      path.moveTo(40, 6);
      path.lineTo(33, 16);
      path.lineTo(47, 16);
      path.close();
      canvas.drawPath(path, arrowPaint);
      
      // Draw simple truck body facing North
      final Paint truckPaint = Paint()..color = Colors.white;
      
      // Cargo box
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(30, 24, 20, 24),
          const Radius.circular(2.5),
        ),
        truckPaint,
      );
      
      // Cabin
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(32, 16, 16, 7),
          const Radius.circular(1.5),
        ),
        truckPaint,
      );
      
      // Connection hitch
      canvas.drawRect(const Rect.fromLTWH(38, 23, 4, 1), truckPaint);
      
      // Wheels side decorations
      final Paint wheelPaint = Paint()..color = const Color(0xFF0D47A1);
      canvas.drawCircle(const Offset(29, 31), 2.5, wheelPaint);
      canvas.drawCircle(const Offset(29, 43), 2.5, wheelPaint);
      canvas.drawCircle(const Offset(51, 31), 2.5, wheelPaint);
      canvas.drawCircle(const Offset(51, 43), 2.5, wheelPaint);

      final ui.Image image = await pictureRecorder.endRecording().toImage(80, 80);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData != null && mounted) {
        setState(() {
          _truckIcon = BitmapDescriptor.bytes(byteData.buffer.asUint8List());
        });
      }
    } catch (e) {
      debugPrint('[TRACK-VEHICLE-ERROR] Custom canvas marker loading failed: $e');
    }
  }

  Future<LatLng?> _geocodeAddress(String address) async {
    // 1. Try system geocoder first
    try {
      final locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        return LatLng(locations[0].latitude, locations[0].longitude);
      }
    } catch (e) {
      debugPrint('[GEO-ERROR] System geocoding failed for "$address": $e. Trying Google Geocoding API...');
    }

    // 2. Fallback to Google Geocoding API Web Service
    try {
      final encodedAddress = Uri.encodeComponent(address);
      final url = "https://maps.googleapis.com/maps/api/geocode/json?address=$encodedAddress&key=${ApiKeys.googleMapsKey}";
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final loc = data['results'][0]['geometry']['location'];
          final double lat = double.parse(loc['lat'].toString());
          final double lng = double.parse(loc['lng'].toString());
          debugPrint('[GEO-SUCCESS] Google Geocoding API resolved "$address" to $lat, $lng');
          return LatLng(lat, lng);
        } else {
          debugPrint('[GEO-ERROR] Google Geocoding API response error for "$address": ${data['status']}');
        }
      }
    } catch (e) {
      debugPrint('[GEO-ERROR] Google Geocoding API failed for "$address": $e');
    }
    return null;
  }

  /// Fetch full route polyline coordinates from pickup to drop, or driver location to destination if active
  Future<void> _fetchFullRoute() async {
    _pickupLat ??= double.tryParse(widget.loadData['fromLat']?.toString() ?? '');
    _pickupLng ??= double.tryParse(widget.loadData['fromLng']?.toString() ?? '');
    _dropLat ??= double.tryParse(widget.loadData['toLat']?.toString() ?? '');
    _dropLng ??= double.tryParse(widget.loadData['toLng']?.toString() ?? '');

    // Geocoding fallback for source location if missing
    if (_pickupLat == null || _pickupLng == null) {
      final String? fromLoc = widget.loadData['fromLocation']?.toString();
      if (fromLoc != null && fromLoc.isNotEmpty) {
        final resolved = await _geocodeAddress(fromLoc);
        if (resolved != null) {
          _pickupLat = resolved.latitude;
          _pickupLng = resolved.longitude;
          debugPrint('[TRACK-VEHICLE-GEO] Geocoded pickup: $_pickupLat, $_pickupLng');
        }
      }
    }

    // Geocoding fallback for destination location if missing
    if (_dropLat == null || _dropLng == null) {
      final String? toLoc = widget.loadData['toLocation']?.toString();
      if (toLoc != null && toLoc.isNotEmpty) {
        final resolved = await _geocodeAddress(toLoc);
        if (resolved != null) {
          _dropLat = resolved.latitude;
          _dropLng = resolved.longitude;
          debugPrint('[TRACK-VEHICLE-GEO] Geocoded drop: $_dropLat, $_dropLng');
        }
      }
    }

    final double? originLat = (_tripStatus == 'active' && _driverLat != null) ? _driverLat : _pickupLat;
    final double? originLng = (_tripStatus == 'active' && _driverLng != null) ? _driverLng : _pickupLng;
    final double? destLat = _dropLat;
    final double? destLng = _dropLng;

    if (originLat != null && originLng != null && destLat != null && destLng != null) {
      if (mounted) {
        setState(() {
          _calculatingRoute = true;
        });
      }

      final result = await DirectionsService.getDirections(originLat, originLng, destLat, destLng);

      if (mounted) {
        setState(() {
          _calculatingRoute = false;
          if (result != null) {
            polylineCoordinates = result.points;
            _roadDistanceText = result.distanceText;
            _roadDurationText = result.durationText;
            _updateMapData();
          }
        });
      }
    }
  }

  Future<void> _fetchTrackingInfo({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _isLoading = true;
      });
    }

    final loadId = widget.loadData['id'] ?? widget.loadData['_id'];

    try {
      final response = await _api.get('/tracking/$loadId');
      
      if (response.statusCode == 200 && response.data != null) {
        final trackInfo = response.data['tracking'];
        if (trackInfo != null) {
          final nextLat = double.tryParse(trackInfo['latitude'].toString());
          final nextLng = double.tryParse(trackInfo['longitude'].toString());
          _tripStatus = trackInfo['tripStatus'];
          
          if (trackInfo['timestamp'] != null) {
            _lastUpdated = DateTime.tryParse(trackInfo['timestamp'].toString());
          }

          if (nextLat != null && nextLng != null) {
            final nextPos = LatLng(nextLat, nextLng);

            if (_driverLat == null || _driverLng == null) {
              _driverLat = nextLat;
              _driverLng = nextLng;
              _oldDriverPosition = nextPos;
              _targetDriverPosition = nextPos;
            } else {
              // Location coordinates changed, trigger smooth movement interpolation
              _oldDriverPosition = LatLng(_driverLat!, _driverLng!);
              _targetDriverPosition = nextPos;

              // Calculate Bearing/Angle of movement
              _markerRotation = _calculateBearing(
                _oldDriverPosition!.latitude,
                _oldDriverPosition!.longitude,
                _targetDriverPosition!.latitude,
                _targetDriverPosition!.longitude,
              );

              // Animate marker over 1.5s
              _movementController?.forward(from: 0.0);
            }

            if (_tripStatus == 'active') {
              _fetchFullRoute();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[TRACK-VEHICLE] Error fetching tracking: $e');
      if (!quiet) {
        _tripStatus = 'not_started';
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _updateMapData();
        });
        
        // Auto fit coordinates once on screen load
        if (_isFirstLoad && !_isLoading) {
          _isFirstLoad = false;
          // Short delay to let Map Controller register safely
          Future.delayed(const Duration(milliseconds: 600), () {
            _fitMapToMarkers();
          });
        }
      }
    }
  }

  void _startFirestoreListener() {
    final loadId = widget.loadData['id'] ?? widget.loadData['_id'];
    _firestoreSub?.cancel();
    
    _firestoreSub = FirebaseFirestore.instance
        .collection('activeTrips')
        .doc(loadId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists) return;
      final data = doc.data();
      if (data == null) return;

      final GeoPoint? geo = data['currentLocation'];
      final String? status = data['status'];
      final Timestamp? lastUpdatedTs = data['lastUpdated'];
      
      if (geo != null) {
        final double nextLat = geo.latitude;
        final double nextLng = geo.longitude;
        final nextPos = LatLng(nextLat, nextLng);
        
        if (mounted) {
          setState(() {
            _tripStatus = status == 'completed' ? 'stopped' : 'active';
            
            if (lastUpdatedTs != null) {
              _lastUpdated = lastUpdatedTs.toDate();
            } else {
              _lastUpdated = DateTime.now();
            }

            if (_driverLat == null || _driverLng == null) {
              _driverLat = nextLat;
              _driverLng = nextLng;
              _oldDriverPosition = nextPos;
              _targetDriverPosition = nextPos;
            } else {
              _oldDriverPosition = LatLng(_driverLat!, _driverLng!);
              _targetDriverPosition = nextPos;
              
              if (data['heading'] != null) {
                _markerRotation = double.tryParse(data['heading'].toString()) ?? 0.0;
              } else {
                _markerRotation = _calculateBearing(
                  _oldDriverPosition!.latitude,
                  _oldDriverPosition!.longitude,
                  _targetDriverPosition!.latitude,
                  _targetDriverPosition!.longitude,
                );
              }
              
              _movementController?.forward(from: 0.0);
            }

            if (data['eta'] != null && data['eta'] != 'Calculating...') {
              _roadDurationText = data['eta'].toString();
            }
            if (data['distance'] != null && data['distance'] != '--') {
              _roadDistanceText = data['distance'].toString();
            }

            _isLoading = false;
            _updateMapData();
          });

          if (_tripStatus == 'active') {
            _fetchFullRoute();
          }
        }
      }
    }, onError: (err) {
      debugPrint('[TRACK-VEHICLE-FIRESTORE] Real-time stream failed: $err');
    });
  }


  void _updateMapData() {
    _markers.clear();
    
    final double? fromLat = _pickupLat ?? double.tryParse(widget.loadData['fromLat']?.toString() ?? '');
    final double? fromLng = _pickupLng ?? double.tryParse(widget.loadData['fromLng']?.toString() ?? '');
    final double? toLat = _dropLat ?? double.tryParse(widget.loadData['toLat']?.toString() ?? '');
    final double? toLng = _dropLng ?? double.tryParse(widget.loadData['toLng']?.toString() ?? '');

    // 1. Add Pickup Marker
    if (fromLat != null && fromLng != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(fromLat, fromLng),
          infoWindow: InfoWindow(title: 'Pickup Location', snippet: widget.loadData['fromLocation']),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
    }

    // 2. Add Drop/Destination Marker
    if (toLat != null && toLng != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('drop'),
          position: LatLng(toLat, toLng),
          infoWindow: InfoWindow(title: 'Delivery Destination', snippet: widget.loadData['toLocation']),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }

    // 3. Add Driver Custom Animated Marker
    if (_tripStatus == 'active' && _driverLat != null && _driverLng != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: LatLng(_driverLat!, _driverLng!),
          infoWindow: InfoWindow(
            title: 'Driver: ${widget.loadData['driverName'] ?? "Active Truck"}',
            snippet: _roadDurationText != null ? 'ETA: $_roadDurationText' : 'Live Location',
          ),
          icon: _truckIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          rotation: _markerRotation,
          anchor: const Offset(0.5, 0.5), // Center truck on coordinates
          flat: true, // Flat rendering allows dynamic rotation with map alignment
        ),
      );
    }

    // 4. Draw Polylines
    _polylines.clear();
    
    // Add real full blue polyline route (Premium Logistics Glow styling)
    if (polylineCoordinates.isNotEmpty) {
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('full_route'),
          points: polylineCoordinates,
          color: const Color(0xFF2196F3),
          width: 7,
          geodesic: true,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
    }

    // Fallback straight dashed polyline if Directions API fails or hasn't loaded
    if (polylineCoordinates.isEmpty && _tripStatus == 'active' && _driverLat != null && _driverLng != null && toLat != null && toLng != null) {
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route_to_destination'),
          points: [LatLng(_driverLat!, _driverLng!), LatLng(toLat, toLng)],
          color: const Color(0xFF2196F3),
          width: 7,
          geodesic: true,
          patterns: [PatternItem.dash(15), PatternItem.gap(10)],
        ),
      );
    }
  }

  void _fitMapToMarkers() {
    if (_mapController == null) return;

    List<LatLng> boundsPoints = [];
    
    // Add all route polyline points to bounds calculation
    if (polylineCoordinates.isNotEmpty) {
      boundsPoints.addAll(polylineCoordinates);
    } else {
      // Fallback to markers if route polyline is empty
      for (final marker in _markers) {
        boundsPoints.add(marker.position);
      }
    }

    // Include moving truck location in the bounds
    if (_driverLat != null && _driverLng != null) {
      boundsPoints.add(LatLng(_driverLat!, _driverLng!));
    }

    if (boundsPoints.isEmpty) return;

    double? minLat, maxLat, minLng, maxLng;

    for (final pt in boundsPoints) {
      if (minLat == null || pt.latitude < minLat) minLat = pt.latitude;
      if (maxLat == null || pt.latitude > maxLat) maxLat = pt.latitude;
      if (minLng == null || pt.longitude < minLng) minLng = pt.longitude;
      if (maxLng == null || pt.longitude > maxLng) maxLng = pt.longitude;
    }

    if (minLat != null && maxLat != null && minLng != null && maxLng != null) {
      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );

      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 75));
    }
  }

  /// Calculates dynamic bearing between two coordinates in degrees
  double _calculateBearing(double startLat, double startLng, double endLat, double endLng) {
    double lat1 = startLat * math.pi / 180.0;
    double lng1 = startLng * math.pi / 180.0;
    double lat2 = endLat * math.pi / 180.0;
    double lng2 = endLng * math.pi / 180.0;

    double dLon = lng2 - lng1;

    double y = math.sin(dLon) * math.cos(lat2);
    double x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    double brng = math.atan2(y, x);
    return (brng * 180.0 / math.pi + 360.0) % 360.0;
  }

  /// Determine trip progress index dynamically from coordinates
  int _getCurrentStatusIndex() {
    final status = widget.loadData['status']?.toString().toLowerCase();
    if (status == 'completed' || _tripStatus == 'stopped') {
      return 4; // Completed
    }
    if (_tripStatus != 'active' || _driverLat == null || _driverLng == null) {
      return 0; // Waiting
    }

    final double? fromLat = _pickupLat ?? double.tryParse(widget.loadData['fromLat']?.toString() ?? '');
    final double? fromLng = _pickupLng ?? double.tryParse(widget.loadData['fromLng']?.toString() ?? '');
    final double? toLat = _dropLat ?? double.tryParse(widget.loadData['toLat']?.toString() ?? '');
    final double? toLng = _dropLng ?? double.tryParse(widget.loadData['toLng']?.toString() ?? '');

    if (toLat != null && toLng != null) {
      final double distanceToDrop = Geolocator.distanceBetween(_driverLat!, _driverLng!, toLat, toLng);
      if (distanceToDrop < 400) {
        return 3; // Reached Destination
      }
    }

    if (fromLat != null && fromLng != null) {
      final double distanceFromPickup = Geolocator.distanceBetween(_driverLat!, _driverLng!, fromLat, fromLng);
      if (distanceFromPickup < 1200) {
        return 1; // Trip Started
      }
    }

    return 2; // Moving
  }

  String _formatTimeDifference(DateTime? time) {
    if (time == null) return 'N/A';
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 15) {
      return 'Just now';
    } else if (diff.inMinutes < 1) {
      return '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else {
      return '${diff.inHours}h ago';
    }
  }

  Widget _buildOnlineBadge() {
    if (_lastUpdated == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'OFFLINE',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    
    final diff = DateTime.now().difference(_lastUpdated!);
    final isOnline = diff.inSeconds <= 60;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isOnline ? Colors.green.withValues(alpha: 0.15) : Colors.white10,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOnline ? Colors.green.withValues(alpha: 0.4) : Colors.white24,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          isOnline
              ? Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.8),
                        blurRadius: 6,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                )
              : Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
          const SizedBox(width: 6),
          Text(
            isOnline ? 'LIVE' : 'OFFLINE',
            style: TextStyle(
              color: isOnline ? const Color(0xFF81C784) : Colors.grey,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusStepper(int currentIndex) {
    final List<String> steps = ['Waiting', 'Started', 'Moving', 'Reached', 'Completed'];
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF282F3E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF384256)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TRIP TIMELINE',
                style: TextStyle(fontSize: 10, color: Color(0xFF9EABB8), fontWeight: FontWeight.bold, letterSpacing: 0.8),
              ),
              _buildOnlineBadge(),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(steps.length, (index) {
              final isPassed = index <= currentIndex;
              final isCurrent = index == currentIndex;
              final stepColor = isCurrent 
                  ? const Color(0xFF2196F3) 
                  : (isPassed ? const Color(0xFF4CAF50) : const Color(0xFF475569));
                  
              return Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 3,
                            color: index == 0 
                                ? Colors.transparent 
                                : (index <= currentIndex ? const Color(0xFF4CAF50) : const Color(0xFF475569)),
                          ),
                        ),
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: isCurrent ? Colors.white : stepColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: stepColor,
                              width: isCurrent ? 5 : 2,
                            ),
                            boxShadow: isCurrent ? [
                              BoxShadow(
                                color: const Color(0xFF2196F3).withValues(alpha: 0.5),
                                blurRadius: 8,
                                spreadRadius: 2,
                              )
                            ] : null,
                          ),
                        ),
                        Expanded(
                          child: Container(
                            height: 3,
                            color: index == steps.length - 1 
                                ? Colors.transparent 
                                : (index < currentIndex ? const Color(0xFF4CAF50) : const Color(0xFF475569)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      steps[index],
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                        color: isCurrent 
                            ? const Color(0xFF64B5F6) 
                            : (isPassed ? Colors.white70 : const Color(0xFF9EABB8)),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteProgressBar(double progress) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF282F3E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF384256)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ROUTE PROGRESS',
                style: TextStyle(fontSize: 10, color: Color(0xFF9EABB8), fontWeight: FontWeight.bold, letterSpacing: 0.8),
              ),
              Text(
                '${(progress * 100).toStringAsFixed(0)}% Completed',
                style: const TextStyle(fontSize: 11, color: Color(0xFF64B5F6), fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double? fromLat = _pickupLat ?? double.tryParse(widget.loadData['fromLat']?.toString() ?? '');
    final double? fromLng = _pickupLng ?? double.tryParse(widget.loadData['fromLng']?.toString() ?? '');

    final CameraPosition initialCamera = CameraPosition(
      target: fromLat != null && fromLng != null ? LatLng(fromLat, fromLng) : const LatLng(15.6244, 76.9034),
      zoom: 11,
    );

    final isTripActive = _tripStatus == 'active' && _driverLat != null && _driverLng != null;
    final currentStatusIndex = _getCurrentStatusIndex();

    // Route progress calculation
    double progressPercent = 0.0;
    if (isTripActive && _roadDistanceText != null && widget.loadData['distance'] != null) {
      final totalDist = double.tryParse(widget.loadData['distance'].toString().replaceAll(RegExp(r'[^0-9.]'), ''));
      final remDist = double.tryParse(_roadDistanceText!.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (totalDist != null && remDist != null && totalDist > 0) {
        progressPercent = ((totalDist - remDist) / totalDist).clamp(0.0, 1.0);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Trip Tracking', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF1E222B),
        foregroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            onPressed: () => _fetchTrackingInfo(quiet: false),
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: _isLoading && polylineCoordinates.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // 1. Google Map View
                GoogleMap(
                  initialCameraPosition: initialCamera,
                  markers: _markers,
                  polylines: _polylines,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  style: _darkMapStyle,
                  onMapCreated: (controller) {
                    _mapController = controller;
                    setState(() {
                      _updateMapData();
                    });
                  },
                ),

                // 2. Map Floating Controls (Recenter camera)
                Positioned(
                  bottom: 275,
                  right: 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E222B),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF384256)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: IconButton(
                      onPressed: _fitMapToMarkers,
                      icon: const Icon(Icons.my_location, color: Color(0xFF2196F3)),
                      tooltip: 'Recenter View',
                    ),
                  ),
                ),

                // 3. Status Banner
                if (!isTripActive)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E222B).withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF384256)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.orange, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _tripStatus == 'stopped' ? 'Trip Completed' : 'Trip Not Started',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _tripStatus == 'stopped'
                                      ? 'The driver completed tracking for this load.'
                                      : 'Waiting for driver to tap "Start Trip" in their app.',
                                  style: const TextStyle(color: Color(0xFF9EABB8), fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 4. Bottom Glassmorphic Info Panel
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E222B),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                      border: const Border(
                        top: BorderSide(color: Color(0xFF384256), width: 1),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Driver and Call Row
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: const Color(0xFF2196F3).withValues(alpha: 0.15),
                              child: const Icon(Icons.local_shipping, color: Color(0xFF2196F3)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.loadData['driverName'] ?? 'Assigned Driver',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                                  ),
                                  Text(
                                    widget.loadData['truckType'] ?? 'Vehicle Details Not Loaded',
                                    style: const TextStyle(color: Color(0xFF9EABB8), fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.loadData['driverPhone'] != null)
                              IconButton(
                                onPressed: () => launchUrl(Uri.parse('tel:${widget.loadData['driverPhone']}')),
                                icon: const Icon(Icons.call, color: Colors.green),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.green.withValues(alpha: 0.15),
                                  padding: const EdgeInsets.all(12),
                                ),
                              ),
                          ],
                        ),
                        const Divider(height: 20, color: Color(0xFF384256)),

                        // Route details
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, color: Color(0xFF9EABB8), size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${widget.loadData['fromLocation']} → ${widget.loadData['toLocation']}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF64B5F6)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Render status stepper timeline
                        _buildStatusStepper(currentStatusIndex),
                        const SizedBox(height: 10),

                        // Route Progress Bar
                        if (isTripActive && _roadDistanceText != null) ...[
                          _buildRouteProgressBar(progressPercent),
                          const SizedBox(height: 10),
                        ],

                        // ETA details panel
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF282F3E),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF384256)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              // Distance Stats
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text('DISTANCE TO GO', style: TextStyle(fontSize: 9, color: Color(0xFF9EABB8), fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                    const SizedBox(height: 6),
                                    _calculatingRoute
                                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                        : Text(
                                            _roadDistanceText != null
                                                ? _roadDistanceText!
                                                : '--',
                                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                                          ),
                                  ],
                                ),
                              ),
                              Container(height: 30, width: 1, color: const Color(0xFF384256)),
                              // Duration Stats
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text('ESTIMATED TIME', style: TextStyle(fontSize: 9, color: Color(0xFF9EABB8), fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                    const SizedBox(height: 6),
                                    _calculatingRoute
                                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                        : Text(
                                            _roadDurationText != null
                                                ? _roadDurationText!
                                                : '--',
                                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF64B5F6)),
                                          ),
                                  ],
                                ),
                              ),
                              Container(height: 30, width: 1, color: const Color(0xFF384256)),
                              // Last Active Stats
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text('LAST UPDATE', style: TextStyle(fontSize: 9, color: Color(0xFF9EABB8), fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                    const SizedBox(height: 6),
                                    Text(
                                      _lastUpdated != null ? _formatTimeDifference(_lastUpdated) : '--',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  static const String _darkMapStyle = r'''
[
  {
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#212121"
      }
    ]
  },
  {
    "elementType": "labels.icon",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#757575"
      }
    ]
  },
  {
    "elementType": "labels.text.stroke",
    "stylers": [
      {
        "color": "#212121"
      }
    ]
  },
  {
    "featureType": "administrative",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#757575"
      }
    ]
  },
  {
    "featureType": "administrative.country",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#9e9e9e"
      }
    ]
  },
  {
    "featureType": "administrative.land_parcel",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "administrative.locality",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#bdbdbd"
      }
    ]
  },
  {
    "featureType": "poi",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#757575"
      }
    ]
  },
  {
    "featureType": "poi.park",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#181818"
      }
    ]
  },
  {
    "featureType": "poi.park",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#616161"
      }
    ]
  },
  {
    "featureType": "poi.park",
    "elementType": "labels.text.stroke",
    "stylers": [
      {
        "color": "#1b1b1b"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "geometry.fill",
    "stylers": [
      {
        "color": "#2c2c2c"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#8a8a8a"
      }
    ]
  },
  {
    "featureType": "road.arterial",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#373737"
      }
    ]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#3c3c3c"
      }
    ]
  },
  {
    "featureType": "road.highway.controlled_access",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#4e4e4e"
      }
    ]
  },
  {
    "featureType": "road.local",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#616161"
      }
    ]
  },
  {
    "featureType": "transit",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#757575"
      }
    ]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#000000"
      }
    ]
  },
  {
    "featureType": "water",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#3d3d3d"
      }
    ]
  }
]
  ''';
}
