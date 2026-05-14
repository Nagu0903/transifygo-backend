import 'package:transify_app/core/network/api_service.dart';

class AdminRepository {
  final ApiService _apiService = ApiService();

  Future<Map<String, dynamic>> fetchStats() async {
    try {
      final response = await _apiService.get('/admin/stats');
      if (response.data['success']) {
        return response.data['stats'];
      }
      throw Exception(response.data['message'] ?? 'Failed to fetch stats');
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchUsers() async {
    try {
      final response = await _apiService.get('/admin/loadowners');
      if (response.data['success']) {
        final List users = response.data['users'];
        return users.map((e) => e as Map<String, dynamic>).toList();
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchDrivers() async {
    try {
      final response = await _apiService.get('/admin/drivers');
      if (response.data['success']) {
        final List drivers = response.data['drivers'];
        return drivers.map((e) => e as Map<String, dynamic>).toList();
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchLoads() async {
    try {
      final response = await _apiService.get('/admin/live-loads');
      if (response.data['success']) {
        final List loads = response.data['loads'];
        return loads.map((e) => e as Map<String, dynamic>).toList();
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteLoad(String loadId) async {
    try {
      await _apiService.delete('/admin/loads/$loadId');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> toggleBlockUser(String userId, bool isBlocked) async {
    try {
      await _apiService.post('/admin/users/$userId/block', {
        'isBlocked': isBlocked,
      }, isPut: true);
    } catch (e) {
      rethrow;
    }
  }
}
