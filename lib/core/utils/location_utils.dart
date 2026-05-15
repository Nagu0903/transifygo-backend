import 'package:geocoding/geocoding.dart';

class LocationUtils {
  /// Formats a [Placemark] into a professional "Village, Taluk, District, State" format.
  /// Handles Plus Codes and small village detection.
  static String formatPlacemark(Placemark place) {
    // 1. Extract potential village/locality names
    String village = _cleanName(place.subLocality);
    String town = _cleanName(place.locality);
    String taluk = _cleanName(place.subAdministrativeArea);
    String district = _cleanName(place.subAdministrativeArea);
    String state = _cleanName(place.administrativeArea);
    String name = _cleanName(place.name);

    // 2. Logic to determine the best "Village/City" name
    String bestLocality = "";
    
    // If subLocality is not a Plus Code and not empty, it's likely the village
    if (village.isNotEmpty && !_isPlusCode(village)) {
      bestLocality = village;
    } else if (town.isNotEmpty && !_isPlusCode(town)) {
      bestLocality = town;
    } else if (name.isNotEmpty && !_isPlusCode(name)) {
      bestLocality = name;
    }

    // 3. Fallback to nearest town if locality is empty
    if (bestLocality.isEmpty) {
      bestLocality = taluk.isNotEmpty ? taluk : (district.isNotEmpty ? district : "Unknown Location");
    }

    // 4. Construct the address parts
    List<String> parts = [];
    
    if (bestLocality.isNotEmpty) parts.add(bestLocality);
    
    // For Karnataka/India, subAdministrativeArea often contains the District.
    // If it's different from the bestLocality, add it.
    if (district.isNotEmpty && district != bestLocality) {
      parts.add(district);
    }
    
    if (state.isNotEmpty) {
      parts.add(state);
    }

    return parts.join(", ");
  }

  /// Extracts just the District and State for backend storage
  static Map<String, String> getDistrictAndState(Placemark place) {
    return {
      'district': place.subAdministrativeArea ?? place.locality ?? "",
      'state': place.administrativeArea ?? "",
    };
  }

  static String _cleanName(String? name) {
    if (name == null || name.isEmpty) return "";
    // Remove common non-useful values
    if (name.toLowerCase() == "unnamed road") return "";
    return name.trim();
  }

  static bool _isPlusCode(String text) {
    // Simple regex for Plus Codes (e.g., VW8F+835 or 8FGHVW8F+835)
    final plusCodeRegex = RegExp(r'^[A-Z0-9]{4,}\+[A-Z0-9]{2,}.*$');
    return plusCodeRegex.hasMatch(text);
  }
}
