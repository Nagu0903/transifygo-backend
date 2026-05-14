import 'package:transify_app/core/network/api_service.dart';

class LoadRepository {
  final ApiService _apiService = ApiService();

  // 1. Post a new load
  Future<void> postLoad(Map<String, dynamic> loadData) async {
    try {
      await _apiService.post('/loads/create', loadData);
    } catch (e) {
      rethrow;
    }
  }

  // 2. Fetch all pending loads (For Driver)
  Future<List<Map<String, dynamic>>> fetchPendingLoads() async {
    try {
      final response = await _apiService.get('/loads');
      if (response.data['success']) {
        final List loads = response.data['loads'];
        return loads.map((e) => e as Map<String, dynamic>).toList();
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  // 3. Accept a load (For Driver)
  Future<void> acceptLoad(String loadId, Map<String, dynamic> driverData) async {
    try {
      // Align with new PUT /api/loads/status/:loadId
      await _apiService.post('/loads/status/$loadId', {
        ...driverData,
        'status': 'accepted',
      }, isPut: true);
    } catch (e) {
      rethrow;
    }
  }

  // 4. Update Load Status (For Owner/Driver)
  Future<void> updateLoadStatus(String loadId, String status, {Map<String, dynamic>? extraData}) async {
    try {
      final Map<String, dynamic> payload = { 'status': status };
      if (extraData != null) payload.addAll(extraData);
      
      await _apiService.post('/loads/status/$loadId', payload, isPut: true);
    } catch (e) {
      rethrow;
    }
  }

  // 5. Fetch My Loads (For Owner)
  Future<List<Map<String, dynamic>>> fetchOwnerLoads(String ownerId) async {
    try {
      final response = await _apiService.get('/loads/my-loads/$ownerId');
      if (response.data['success']) {
        final List loads = response.data['loads'];
        return loads.map((e) => e as Map<String, dynamic>).toList();
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  // 6. Fetch Accepted Loads (For Driver)
  Future<List<Map<String, dynamic>>> fetchDriverLoads(String driverId) async {
    try {
      final response = await _apiService.get('/loads/driver/$driverId');
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
      await _apiService.delete('/loads/$loadId');
    } catch (e) {
      rethrow;
    }
  }
}
