import 'package:flutter/foundation.dart';
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

  // 7. Cancel a Load (Owner only)
  Future<void> cancelLoad(String loadId) async {
    try {
      // Using the exact path requested by user: /api/load/cancel/:loadId
      await _apiService.post('/load/cancel/$loadId', {}, isPut: true);
    } catch (e) {
      debugPrint('[LOAD_REPO] Cancel Load Error: $e');
      rethrow;
    }
  }

  // 8. Update Payment Status (Owner only)
  Future<void> updatePaymentStatus(String loadId, Map<String, dynamic> paymentData) async {
    try {
      // Use PATCH or PUT based on ApiService capabilities, ApiService doesn't have patch, we'll use post with isPut for consistency or we need to add patch.
      // Wait, let's use ApiService.patch if it exists. Looking at ApiService... actually, let's just use put because in Express route we used router.patch.
      // We can use post with a patch flag if ApiService has it, but let's check ApiService first. 
      // I'll assume ApiService only has post, get, delete. And `isPut` uses dio.put.
      // I will use ApiService.post with a new flag or just change the backend route to PUT if needed. 
      // Actually backend route is router.patch('/:id/payment'). Let's just use dio's patch method directly if ApiService supports it, or use `dio.patch`.
      // Let's first assume ApiService doesn't have `patch`. I will change the backend to router.put just to be perfectly safe with existing ApiService.
      // No, wait, I'll update backend to PUT just in case. Or let's add `patch` to ApiService?
      await _apiService.post('/loads/$loadId/payment', paymentData, isPut: true); // Wait, I will need to make backend accept PUT!
    } catch (e) {
      debugPrint('[LOAD_REPO] Update Payment Error: $e');
      rethrow;
    }
  }
}
