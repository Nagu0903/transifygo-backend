import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:transify_app/core/constants/app_colors.dart';
import 'package:transify_app/core/network/api_service.dart';
import 'package:transify_app/core/services/directions_service.dart';

class AdminFleetMapScreen extends StatefulWidget {
  const AdminFleetMapScreen({super.key});

  @override
  State<AdminFleetMapScreen> createState() => _AdminFleetMapScreenState();
}

class _AdminFleetMapScreenState extends State<AdminFleetMapScreen> {
  final ApiService _api = ApiService();
  GoogleMapController? _mapController;
  Timer? _pollingTimer;

  bool _isLoading = true;
  List<Map<String, dynamic>> _activeTrips = [];
  Map<String, dynamic>? _selectedTrip;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  
  // Tracked selected route polylines
  List<LatLng> _selectedRoutePoints = [];
  bool _fetchingRoute = false;

  BitmapDescriptor? _truckIcon;
  BitmapDescriptor? _standbyIcon;

  StreamSubscription<QuerySnapshot>? _firestoreSub;

  @override
  void initState() {
    super.initState();
    _loadCustomMarkerIcons();
    _fetchFleetData().then((_) {
      _startFirestoreListener();
    });
    
    // Background polling every 15 seconds
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _fetchFleetData(quiet: true),
    );
  }

  @override
  void dispose() {
    _firestoreSub?.cancel();
    _pollingTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  /// Create custom canvas marker icons dynamically
  Future<void> _loadCustomMarkerIcons() async {
    try {
      // 1. Truck Icon (Active Tracking)
      final ui.PictureRecorder recorder1 = ui.PictureRecorder();
      final Canvas canvas1 = Canvas(recorder1);
      final Paint bluePaint = Paint()..color = AppColors.primaryBlue;
      final Paint whiteBorder = Paint()
        ..color = Colors.white
        ..strokeWidth = 3.5
        ..style = PaintingStyle.stroke;

      canvas1.drawCircle(const Offset(40, 40), 28, bluePaint);
      canvas1.drawCircle(const Offset(40, 40), 28, whiteBorder);
      
      final Paint truckPaint = Paint()..color = Colors.white;
      canvas1.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(30, 24, 20, 22), const Radius.circular(2)), truckPaint);
      canvas1.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(32, 17, 16, 6), const Radius.circular(1)), truckPaint);
      canvas1.drawRect(const Rect.fromLTWH(38, 23, 4, 1), truckPaint);

      final ui.Image img1 = await recorder1.endRecording().toImage(80, 80);
      final byteData1 = await img1.toByteData(format: ui.ImageByteFormat.png);
      
      // 2. Standby/Waiting Icon (Accepted but no location data)
      final ui.PictureRecorder recorder2 = ui.PictureRecorder();
      final Canvas canvas2 = Canvas(recorder2);
      final Paint orangePaint = Paint()..color = Colors.orange.shade700;

      canvas2.drawCircle(const Offset(40, 40), 28, orangePaint);
      canvas2.drawCircle(const Offset(40, 40), 28, whiteBorder);
      
      canvas2.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(30, 24, 20, 22), const Radius.circular(2)), truckPaint);
      canvas2.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(32, 17, 16, 6), const Radius.circular(1)), truckPaint);
      canvas2.drawRect(const Rect.fromLTWH(38, 23, 4, 1), truckPaint);

      final ui.Image img2 = await recorder2.endRecording().toImage(80, 80);
      final byteData2 = await img2.toByteData(format: ui.ImageByteFormat.png);

      if (mounted && byteData1 != null && byteData2 != null) {
        setState(() {
          _truckIcon = BitmapDescriptor.bytes(byteData1.buffer.asUint8List());
          _standbyIcon = BitmapDescriptor.bytes(byteData2.buffer.asUint8List());
        });
      }
    } catch (e) {
      debugPrint('[ADMIN-FLEET-ERROR] Loading custom markers failed: $e');
    }
  }

  /// Get active loads and tracking values from endpoint
  Future<void> _fetchFleetData({bool quiet = false}) async {
    if (!quiet) {
      setState(() => _isLoading = true);
    }

    try {
      final response = await _api.get('/tracking/active/all');
      
      if (response.statusCode == 200 && response.data != null) {
        final List tripsData = response.data['trips'] ?? [];
        
        if (mounted) {
          setState(() {
            _activeTrips = tripsData.map((e) => e as Map<String, dynamic>).toList();
            _updateMapMarkers();
            
            // Re-sync selected trip details
            if (_selectedTrip != null) {
              final selectedId = _selectedTrip!['load']['_id'] ?? _selectedTrip!['load']['id'];
              final updated = _activeTrips.firstWhere(
                (element) => (element['load']['_id'] ?? element['load']['id']) == selectedId,
                orElse: () => {},
              );
              if (updated.isNotEmpty) {
                _selectedTrip = updated;
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint('[ADMIN-FLEET] Error fetching data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _startFirestoreListener() {
    _firestoreSub?.cancel();
    _firestoreSub = FirebaseFirestore.instance
        .collection('activeTrips')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final Map<String, Map<String, dynamic>> firestoreTrackingMap = {};
        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final GeoPoint? geo = data['currentLocation'];
          if (geo != null) {
            firestoreTrackingMap[doc.id] = {
              'latitude': geo.latitude,
              'longitude': geo.longitude,
              'tripStatus': data['status'] == 'completed' ? 'stopped' : 'active',
              'timestamp': (data['lastUpdated'] as Timestamp?)?.toDate().toIso8601String(),
              'driverId': data['driverId'],
              'eta': data['eta'],
            };
          }
        }

        if (mounted) {
          setState(() {
            for (var trip in _activeTrips) {
              final load = trip['load'];
              final loadId = load['_id'] ?? load['id'];
              if (firestoreTrackingMap.containsKey(loadId)) {
                trip['tracking'] = firestoreTrackingMap[loadId];
              }
            }
            _updateMapMarkers();
            
            // Re-sync selected trip details
            if (_selectedTrip != null) {
              final selectedId = _selectedTrip!['load']['_id'] ?? _selectedTrip!['load']['id'];
              final updated = _activeTrips.firstWhere(
                (element) => (element['load']['_id'] ?? element['load']['id']) == selectedId,
                orElse: () => {},
              );
              if (updated.isNotEmpty) {
                _selectedTrip = updated;
              }
            }
          });
        }
      }
    }, onError: (err) {
      debugPrint('[ADMIN-FLEET-FIRESTORE] Real-time fleet sync error: $err');
    });
  }

  /// Compile markers for active and standby trucks
  void _updateMapMarkers() {
    _markers.clear();

    for (final trip in _activeTrips) {
      final load = trip['load'];
      final tracking = trip['tracking'];
      final loadId = load['_id'] ?? load['id'];
      
      final String driverName = load['driverName'] ?? 'Driver Assigned';
      final String routeTitle = '${load['fromLocation']} → ${load['toLocation']}';

      if (tracking != null && tracking['latitude'] != null && tracking['longitude'] != null) {
        // Active truck marker
        final double lat = double.parse(tracking['latitude'].toString());
        final double lng = double.parse(tracking['longitude'].toString());

        _markers.add(
          Marker(
            markerId: MarkerId('active_$loadId'),
            position: LatLng(lat, lng),
            infoWindow: InfoWindow(
              title: 'Driver: $driverName',
              snippet: 'Live Tracking Active • $routeTitle',
            ),
            icon: _truckIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            onTap: () => _onTripSelected(trip),
          ),
        );
      } else {
        // Standby load marker (draw at pickup coordinate)
        final double? lat = double.tryParse(load['fromLat']?.toString() ?? '');
        final double? lng = double.tryParse(load['fromLng']?.toString() ?? '');

        if (lat != null && lng != null) {
          _markers.add(
            Marker(
              markerId: MarkerId('standby_$loadId'),
              position: LatLng(lat, lng),
              infoWindow: InfoWindow(
                title: '$driverName (Standby)',
                snippet: 'Waiting to Start Trip • $routeTitle',
              ),
              icon: _standbyIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
              onTap: () => _onTripSelected(trip),
            ),
          );
        }
      }
    }
  }

  /// Draws route polyline dynamically when a trip is selected
  Future<void> _onTripSelected(Map<String, dynamic> trip) async {
    setState(() {
      _selectedTrip = trip;
      _selectedRoutePoints = [];
      _polylines.clear();
    });

    final load = trip['load'];
    final tracking = trip['tracking'];

    double? startLat = double.tryParse(load['fromLat']?.toString() ?? '');
    double? startLng = double.tryParse(load['fromLng']?.toString() ?? '');
    final double? endLat = double.tryParse(load['toLat']?.toString() ?? '');
    final double? endLng = double.tryParse(load['toLng']?.toString() ?? '');

    // If live location is tracking, draw polyline from truck coordinate to drop destination instead!
    if (tracking != null && tracking['latitude'] != null && tracking['longitude'] != null) {
      startLat = double.parse(tracking['latitude'].toString());
      startLng = double.parse(tracking['longitude'].toString());
    }

    if (startLat != null && startLng != null && endLat != null && endLng != null) {
      setState(() => _fetchingRoute = true);
      final result = await DirectionsService.getDirections(startLat, startLng, endLat, endLng);
      
      if (mounted && result != null) {
        setState(() {
          _selectedRoutePoints = result.points;
          _fetchingRoute = false;
          
          _polylines.add(
            Polyline(
              polylineId: PolylineId('selected_route_${load['_id'] ?? load['id']}'),
              points: _selectedRoutePoints,
              color: const Color(0xFF1E88E5),
              width: 5,
              jointType: JointType.round,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
            ),
          );
          
          _zoomToTrip(startLat!, startLng!, endLat, endLng);
        });
      } else {
        setState(() => _fetchingRoute = false);
      }
    }
  }

  /// Focus map viewport on specific selected trip
  void _zoomToTrip(double sLat, double sLng, double eLat, double eLng) {
    if (_mapController == null) return;
    
    double minLat = math.min(sLat, eLat);
    double maxLat = math.max(sLat, eLat);
    double minLng = math.min(sLng, eLng);
    double maxLng = math.max(sLng, eLng);

    // Zoom map viewport
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80, // padding
      ),
    );
  }

  /// Fits map viewport to contain all currently active driver markers
  void _fitAllMarkers() {
    if (_mapController == null || _markers.isEmpty) return;

    double? minLat, maxLat, minLng, maxLng;
    for (final marker in _markers) {
      final lat = marker.position.latitude;
      final lng = marker.position.longitude;
      if (minLat == null || lat < minLat) minLat = lat;
      if (maxLat == null || lat > maxLat) maxLat = lat;
      if (minLng == null || lng < minLng) minLng = lng;
      if (maxLng == null || lng > maxLng) maxLng = lng;
    }

    if (minLat != null && maxLat != null && minLng != null && maxLng != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          80,
        ),
      );
    }
  }

  String _formatLatency(DateTime? time) {
    if (time == null) return 'No Signal';
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 30) return 'Just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final defaultPos = const LatLng(20.5937, 78.9629); // Center of India default
    final isTripSelected = _selectedTrip != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Fleet Monitor', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        actions: [
          IconButton(
            onPressed: () => _fetchFleetData(quiet: false),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _fitAllMarkers,
            icon: const Icon(Icons.zoom_out_map),
            tooltip: 'Fit All Vehicles',
          ),
        ],
      ),
      body: _isLoading && _activeTrips.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // 1. Map panel
                GoogleMap(
                  initialCameraPosition: CameraPosition(target: defaultPos, zoom: 5),
                  markers: _markers,
                  polylines: _polylines,
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                  onMapCreated: (controller) {
                    _mapController = controller;
                    if (_markers.isNotEmpty) {
                      Future.delayed(const Duration(milliseconds: 500), () {
                        _fitAllMarkers();
                      });
                    }
                  },
                ),

                // 2. Draggable active trip overview list drawer
                _buildTripDrawer(),

                // 3. Floating Detail popup for selected vehicle
                if (isTripSelected) _buildSelectedTripCard(),
              ],
            ),
    );
  }

  Widget _buildSelectedTripCard() {
    final load = _selectedTrip!['load'];
    final tracking = _selectedTrip!['tracking'];
    final isOnline = tracking != null && tracking['timestamp'] != null 
        ? DateTime.now().difference(DateTime.tryParse(tracking['timestamp'])!).inMinutes < 2 
        : false;

    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isOnline ? Colors.green : (tracking != null ? Colors.grey : Colors.orange),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isOnline ? 'TRACKING LIVE' : (tracking != null ? 'OFFLINE' : 'STANDBY (WAITING)'),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isOnline ? Colors.green : (tracking != null ? Colors.grey.shade700 : Colors.orange.shade800),
                      letterSpacing: 0.6,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      setState(() {
                        _selectedTrip = null;
                        _polylines.clear();
                      });
                    },
                    icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${load['fromLocation']} → ${load['toLocation']}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Driver: ${load['driverName'] ?? "N/A"}', style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                  Text('Price: ₹${load['price']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
                ],
              ),
              if (_fetchingRoute) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (tracking != null) ...[
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Last Signal: ${_formatLatency(DateTime.tryParse(tracking['timestamp']))}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    if (load['driverPhone'] != null)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => launchUrl(Uri.parse('tel:${load['driverPhone']}')),
                        icon: const Icon(Icons.call, size: 14, color: Colors.green),
                        label: const Text('Call Driver', style: TextStyle(fontSize: 11, color: Colors.green)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTripDrawer() {
    return DraggableScrollableSheet(
      initialChildSize: 0.28,
      minChildSize: 0.15,
      maxChildSize: 0.70,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -3)),
            ],
          ),
          child: Column(
            children: [
              // Handlebar
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(5)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Active Fleet Monitor (${_activeTrips.length})',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    if (_isLoading)
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
              ),
              const Divider(height: 15),
              Expanded(
                child: _activeTrips.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _activeTrips.length,
                        itemBuilder: (context, index) {
                          final trip = _activeTrips[index];
                          final load = trip['load'];
                          final tracking = trip['tracking'];
                          final loadId = load['_id'] ?? load['id'];
                          
                          final isSelected = _selectedTrip != null && 
                              (_selectedTrip!['load']['_id'] ?? _selectedTrip!['load']['id']) == loadId;

                          final bool trackingActive = tracking != null && tracking['latitude'] != null;
                          final bool isOnline = trackingActive && tracking['timestamp'] != null
                              ? DateTime.now().difference(DateTime.tryParse(tracking['timestamp'])!).inMinutes < 2
                              : false;

                          return Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                              side: isSelected 
                                  ? const BorderSide(color: AppColors.primaryBlue, width: 2)
                                  : BorderSide(color: Colors.grey.shade100, width: 1),
                            ),
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              leading: CircleAvatar(
                                backgroundColor: isOnline
                                    ? Colors.green.withValues(alpha: 0.1)
                                    : (trackingActive ? Colors.grey.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1)),
                                child: Icon(
                                  Icons.local_shipping,
                                  color: isOnline ? Colors.green : (trackingActive ? Colors.grey : Colors.orange),
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                '${load['fromLocation']} → ${load['toLocation']}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    'Material: ${load['material']} • Price: ₹${load['price']}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  Text(
                                    'Driver: ${load['driverName'] ?? "N/A"} • ${load['truckType'] ?? ""}',
                                    style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                                  ),
                                ],
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isOnline
                                      ? Colors.green.withValues(alpha: 0.1)
                                      : (trackingActive ? Colors.grey.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isOnline ? 'LIVE' : (trackingActive ? 'OFFLINE' : 'STANDBY'),
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: isOnline ? Colors.green : (trackingActive ? Colors.grey.shade700 : Colors.orange.shade800),
                                  ),
                                ),
                              ),
                              onTap: () => _onTripSelected(trip),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_shipping_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text(
              'No active trips to monitor right now.',
              style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
