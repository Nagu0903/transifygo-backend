import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider extends ChangeNotifier {
  Locale _currentLocale = const Locale('en');

  LanguageProvider() {
    _loadSavedLanguage();
  }

  Locale get currentLocale => _currentLocale;

  Future<void> _loadSavedLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCode = prefs.getString('selected_language_code');
      if (savedCode != null) {
        _currentLocale = Locale(savedCode);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[LanguageProvider] Error loading saved language: $e');
    }
  }

  Future<void> changeLanguage(String languageCode) async {
    _currentLocale = Locale(languageCode);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_language_code', languageCode);
    } catch (e) {
      debugPrint('[LanguageProvider] Error saving language: $e');
    }
  }

  String translate(String key) {
    if (_currentLocale.languageCode == 'kn') {
      return _kannadaValues[key] ?? key;
    }
    return _englishValues[key] ?? key;
  }

  static const Map<String, String> _englishValues = {
    'app_name': 'TransifyGo',
    'tagline': "India's Smart Transport Network",
    'login': 'Login',
    'signup': 'Sign Up',
    'phone_number': 'Phone Number',
    'password': 'Password',
    'pin': '4 Digit PIN',
    'role_selection': 'Select Your Role',
    'load_owner': 'Load Owner',
    'driver': 'Driver',
    'admin': 'Admin',
    'post_load': 'Post Load',
    'post_load_desc': 'Post your load requirements and find verified transporters quickly.',
    'driver_desc': 'Find nearby loads, bid for loads, manage trips, and earn more every day.',
    'my_loads': 'My Loads',
    'profile': 'Profile',
    'from': 'From Location',
    'to': 'To Location',
    'material_type': 'Material Type',
    'weight': 'Weight (Ton/Bags)',
    'vehicle_type': 'Vehicle Type',
    'load_amount': 'Load Amount',
    'notes': 'Notes (Optional)',
    'accept_load': 'Accept Load',
    'call_owner': 'Call Owner',
    'call_driver': 'Call Driver',
    'contact_support': 'Contact Support',
    'logout': 'Logout',
    'find_loads': 'Find Loads',
    'load_statistics': 'Load Statistics',
    'recent_loads': 'Recent Loads',
    'no_loads_found': 'No loads matching your criteria',
    'refresh': 'Refresh',
    'total_loads': 'Total Loads',
    'active_loads': 'Active Loads',
    'accepted': 'Accepted',
    'completed': 'Completed',
    'to_continue': 'to continue',
    'dont_have_account': "Don't have an account?",
    'full_name': 'Full Name',
    'village_city': 'Village/City',
    'vehicle_number': 'Vehicle Number',
    'forgot_password': 'Forgot Password?',
    'reset_password': 'Reset Password',
    'forgot_password_instruction': 'Enter your registered phone number and new 4-digit PIN to reset.',
  };

  static const Map<String, String> _kannadaValues = {
    'app_name': 'TransifyGo',
    'tagline': "ಭಾರತದ ಸ್ಮಾರ್ಟ್ ಸಾರಿಗೆ ನೆಟ್‌ವರ್ಕ್",
    'login': 'ಲಾಗಿನ್',
    'signup': 'ಸೈನ್ ಅಪ್',
    'phone_number': 'ಫೋನ್ ಸಂಖ್ಯೆ',
    'password': 'ಪಾಸ್‌ವರ್ಡ್',
    'pin': '೪ ಅಂಕಿಯ ಪಿನ್',
    'role_selection': 'ನಿಮ್ಮ ಪಾತ್ರವನ್ನು ಆಯ್ಕೆಮಾಡಿ',
    'load_owner': 'ಲೋಡ್ ಮಾಲೀಕರು',
    'driver': 'ಚಾಲಕ',
    'admin': 'ನಿರ್ವಾಹಕ',
    'post_load': 'ಲೋಡ್ ಪೋಸ್ಟ್ ಮಾಡಿ',
    'post_load_desc': 'ನಿಮ್ಮ ಲೋಡ್ ಅವಶ್ಯಕತೆಗಳನ್ನು ಪೋಸ್ಟ್ ಮಾಡಿ ಮತ್ತು ಪರಿಶೀಲಿಸಿದ ಸಾಗಣೆದಾರರನ್ನು ತ್ವರಿತವಾಗಿ ಹುಡುಕಿ.',
    'driver_desc': 'ಹತ್ತಿರದ ಲೋಡ್‌ಗಳನ್ನು ಹುಡುಕಿ, ಲೋಡ್‌ಗಳಿಗೆ ಬಿಡ್ ಮಾಡಿ, ಪ್ರವಾಸಗಳನ್ನು ನಿರ್ವಹಿಸಿ ಮತ್ತು ಪ್ರತಿದಿನ ಹೆಚ್ಚು ಗಳಿಸಿ.',
    'my_loads': 'ನನ್ನ ಲೋಡ್‌ಗಳು',
    'profile': 'ಪ್ರೊಫೈಲ್',
    'from': 'ಎಲ್ಲಿಂದ',
    'to': 'ಎಲ್ಲಿಗೆ',
    'material_type': 'ಸರಕು ಪ್ರಕಾರ',
    'weight': 'ತೂಕ (ಟನ್/ಚೀಲಗಳು)',
    'vehicle_type': 'ವಾಹನ ಪ್ರಕಾರ',
    'load_amount': 'ಲೋಡ್ ಮೊತ್ತ',
    'notes': 'ಟಿಪ್ಪಣಿಗಳು (ಐಚ್ಛಿಕ)',
    'accept_load': 'ಲೋಡ್ ಸ್ವೀಕರಿಸಿ',
    'call_owner': 'ಮಾಲೀಕರಿಗೆ ಕರೆ ಮಾಡಿ',
    'call_driver': 'ಚಾಲಕನಿಗೆ ಕರೆ ಮಾಡಿ',
    'contact_support': 'ಬೆಂಬಲಕ್ಕಾಗಿ ಸಂಪರ್ಕಿಸಿ',
    'logout': 'ಲೋಗೌಟ್',
    'find_loads': 'ಲೋಡ್‌ಗಳನ್ನು ಹುಡುಕಿ',
    'load_statistics': 'ಲೋಡ್ ಅಂಕಿಅಂಶಗಳು',
    'recent_loads': 'ಇತ್ತೀಚಿನ ಲೋಡ್‌ಗಳು',
    'no_loads_found': 'ಯಾವುದೇ ಲೋಡ್‌ಗಳು ಕಂಡುಬಂದಿಲ್ಲ',
    'refresh': 'ಮತ್ತೆ ಲೋಡ್ ಮಾಡಿ',
    'total_loads': 'ಒಟ್ಟು ಲೋಡ್‌ಗಳು',
    'active_loads': 'ಸಕ್ರಿಯ ಲೋಡ್‌ಗಳು',
    'accepted': 'ಸ್ವೀಕರಿಸಲಾಗಿದೆ',
    'completed': 'ಪೂರ್ಣಗೊಂಡಿದೆ',
    'to_continue': 'ಮುಂದುವರಿಸಲು',
    'dont_have_account': 'ಖಾತೆ ಇಲ್ಲವೇ?',
    'full_name': 'ಪೂರ್ಣ ಹೆಸರು',
    'village_city': 'ಗ್ರಾಮ/ನಗರ',
    'vehicle_number': 'ವಾಹನ ಸಂಖ್ಯೆ',
    'forgot_password': 'ಪಾಸ್‌ವರ್ಡ್ ಮರೆತಿರುವಿರಾ?',
    'reset_password': 'ಪಾಸ್‌ವರ್ಡ್ ಮರುಹೊಂದಿಸಿ',
    'forgot_password_instruction': 'ಪಾಸ್‌ವರ್ಡ್ ಮರುಹೊಂದಿಸಲು ನಿಮ್ಮ ನೋಂದಾಯಿತ ಫೋನ್ ಸಂಖ್ಯೆ ಮತ್ತು ಹೊಸ ೪-ಅಂಕಿಯ ಪಿನ್ ನಮೂದಿಸಿ.',
  };
}
