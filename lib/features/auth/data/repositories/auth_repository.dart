import 'package:transify_app/core/network/api_service.dart';
import '../../domain/models/user_model.dart';

class AuthRepository {
  final ApiService _apiService = ApiService();

  Future<UserModel?> login(String phone, String password, String role) async {
    // 1. Check for fallback admin (Development only)
    if (role == 'Admin' && (phone == 'Nagu' || phone == '6363788419') && password == 'Nagu2@2005') {
      return UserModel(
        id: 'admin_fallback',
        name: 'Super Admin',
        phone: phone,
        password: password,
        role: 'Admin',
        isBlocked: false,
      );
    }

    // 2. Call Node.js Backend
    try {
      final response = await _apiService.post('/auth/login', {
        'phone': phone,
        'password': password,
        'role': role,
      });

      if (response.data['success']) {
        final userData = response.data['user'];
        return UserModel.fromMap(userData, userData['id'] ?? userData['_id']);
      }
      return null;
    } catch (e) {
      rethrow; // Pass error up to Bloc
    }
  }

  Future<bool> checkUserExists(String phone, String role) async {
    // Usually handled by signup API returning 400 if user exists
    return false; 
  }

  Future<UserModel> signup(UserModel user) async {
    try {
      final response = await _apiService.post('/auth/signup', {
        'name': user.name,
        'fullName': user.name, // Support both
        'phone': user.phone,
        'password': user.password,
        'pin': user.password, // Support both
        'role': user.role,
        'city': user.city,
        'truckType': user.truckType,
        'truckNumber': user.truckNumber,
      });

      if (response.data['success']) {
        final userData = response.data['user'];
        return UserModel.fromMap(userData, userData['id'] ?? userData['_id']);
      }
      throw 'Signup failed';
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> resetPassword(String phone, String role, String newPassword) async {
    try {
      final response = await _apiService.post('/auth/forgot-password', {
        'phone': phone,
        'newPin': newPassword,
      });
      return response.data['success'] == true;
    } catch (e) {
      rethrow;
    }
  }
}
