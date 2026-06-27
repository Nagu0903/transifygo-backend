import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:transify_app/core/constants/api_keys.dart';

import 'package:flutter_polyline_points/flutter_polyline_points.dart';

class DirectionsResult {
  final List<LatLng> points;
  final String? distanceText;
  final String? durationText;

  DirectionsResult({required this.points, this.distanceText, this.durationText});
}

class DirectionsService {
  static const String _baseUrl = "https://maps.googleapis.com/maps/api/directions/json";

  /// Fetches the route coordinates and overview stats between two points
  static Future<DirectionsResult?> getDirections(
    double startLat, 
    double startLng, 
    double endLat, 
    double endLng
  ) async {
    try {
      final String url = "$_baseUrl?origin=$startLat,$startLng&destination=$endLat,$endLng&key=${ApiKeys.googleMapsKey}";
      
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          
          // Get overview polyline
          final String encodedPolyline = route['overview_polyline']['points'];
          final polylinePoints = PolylinePoints();
          final List<PointLatLng> decodedPoints = polylinePoints.decodePolyline(encodedPolyline);
          final List<LatLng> points = decodedPoints.map((pt) => LatLng(pt.latitude, pt.longitude)).toList();
          
          // Get distance and duration details from the first leg
          String? distanceText;
          String? durationText;
          if (route['legs'] != null && route['legs'].isNotEmpty) {
            final leg = route['legs'][0];
            distanceText = leg['distance']?['text'];
            durationText = leg['duration']?['text'];
          }
          
          return DirectionsResult(
            points: points,
            distanceText: distanceText,
            durationText: durationText,
          );
        } else {
          debugPrint('Directions API response error: ${data['status']} - ${data['error_message'] ?? ""}');
        }
      }
      return null;
    } catch (e) {
      debugPrint('Directions Service Error: $e');
      return null;
    }
  }

  /// Pure Dart implementation of the Google Polyline Decoding Algorithm
  static List<LatLng> decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      poly.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return poly;
  }
}
