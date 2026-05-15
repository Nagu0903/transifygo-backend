import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:transify_app/core/constants/api_keys.dart';

class DistanceMatrixService {
  static const String _baseUrl = "https://maps.googleapis.com/maps/api/distancematrix/json";

  /// Fetches real road distance and duration between two coordinates
  static Future<Map<String, dynamic>?> getDistance(
    double startLat, 
    double startLng, 
    double endLat, 
    double endLng
  ) async {
    try {
      final String url = "$_baseUrl?origins=$startLat,$startLng&destinations=$endLat,$endLng&key=${ApiKeys.googleMapsKey}";
      
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' && data['rows'].isNotEmpty) {
          final element = data['rows'][0]['elements'][0];
          
          if (element['status'] == 'OK') {
            return {
              'distance_text': element['distance']['text'],
              'distance_value': (element['distance']['value'] / 1000.0), // Convert meters to km
              'duration_text': element['duration']['text'],
            };
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('Distance Matrix Error: $e');
      return null;
    }
  }
}
