import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keyUserUid = 'user_uid';
  static const String _keyUserRole = 'user_role';
  static const String _keyUserName = 'user_name';
  static const String _keyUserPhone = 'user_phone';
  static const String _keyToken = 'jwt_token';

  static Future<void> saveSession({
    required String uid,
    required String role,
    required String name,
    required String phone,
    String? token,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, true);
    await prefs.setString(_keyUserUid, uid);
    await prefs.setString(_keyUserRole, role);
    await prefs.setString(_keyUserName, name);
    await prefs.setString(_keyUserPhone, phone);
    if (token != null) await prefs.setString(_keyToken, token);
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsLoggedIn) ?? false;
  }

  static Future<Map<String, String?>> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'uid': prefs.getString(_keyUserUid),
      'role': prefs.getString(_keyUserRole),
      'name': prefs.getString(_keyUserName),
      'phone': prefs.getString(_keyUserPhone),
      'token': prefs.getString(_keyToken),
    };
  }
}
