import 'package:flutter/material.dart';
import 'package:transify_app/features/admin/data/repositories/admin_repository.dart';
import 'package:transify_app/features/auth/presentation/screens/role_selection_screen.dart';
import 'package:transify_app/core/constants/app_colors.dart';
import 'package:transify_app/core/utils/snackbar_utils.dart';
import 'package:transify_app/features/admin/presentation/screens/admin_fleet_map_screen.dart';


class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final AdminRepository _adminRepo = AdminRepository();
  bool _isLoading = true;
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _recentLoads = [];
  List<Map<String, dynamic>> _recentUsers = [];
  List<Map<String, dynamic>> _bids = [];

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    setState(() => _isLoading = true);
    try {
      final stats = await _adminRepo.fetchStats();
      final loads = await _adminRepo.fetchLoads();
      final users = await _adminRepo.fetchUsers();
      final bids = await _adminRepo.fetchBids();
      
      if (mounted) {
        setState(() {
          _stats = stats;
          _recentLoads = loads;
          _recentUsers = users;
          _bids = bids;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        SnackBarUtils.showError(context, 'Error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminFleetMapScreen())),
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Live Fleet Monitor Map',
          ),
          IconButton(onPressed: _refreshData, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const RoleSelectionScreen()), (route) => false),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _refreshData,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatGrid(),
                  const SizedBox(height: 32),
                  _buildSectionTitle('Live Loads Monitoring', Icons.local_shipping),
                  const SizedBox(height: 16),
                  _buildLoadMonitor(),
                  const SizedBox(height: 32),
                  _buildSectionTitle('Pending Bids Approval', Icons.gavel),
                  const SizedBox(height: 16),
                  _buildBidMonitor(),
                  const SizedBox(height: 32),
                  _buildSectionTitle('User Management', Icons.people),
                  const SizedBox(height: 16),
                  _buildUserList(),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primaryBlue, size: 24),
        const SizedBox(width: 12),
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildStatGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard('Total Users', _stats['totalUsers']?.toString() ?? '0', Colors.blue, Icons.group),
        _buildStatCard('Drivers', _stats['totalDrivers']?.toString() ?? '0', Colors.purple, Icons.drive_eta),
        _buildStatCard('Load Owners', _stats['totalLoadOwners']?.toString() ?? '0', Colors.teal, Icons.person),
        _buildStatCard('Pending Loads', _stats['pendingLoads']?.toString() ?? '0', Colors.orange, Icons.pending_actions),
        _buildStatCard('Accepted', _stats['acceptedLoads']?.toString() ?? '0', Colors.green, Icons.check_circle_outline),
        _buildStatCard('Completed', _stats['completedLoads']?.toString() ?? '0', Colors.indigo, Icons.task_alt),
        _buildStatCard('Cancelled', _stats['cancelledLoads']?.toString() ?? '0', Colors.red, Icons.cancel_outlined),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4)),
        ],
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildLoadMonitor() {
    if (_recentLoads.isEmpty) {
      return _buildEmptyState('No loads found');
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _recentLoads.length > 5 ? 5 : _recentLoads.length,
      itemBuilder: (context, index) {
        final data = _recentLoads[index];
        final loadId = data['_id'] ?? data['id'];
        final status = (data['status'] ?? 'pending').toString().toLowerCase();
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: _getStatusColor(status).withValues(alpha: 0.1),
              child: Icon(Icons.local_shipping, color: _getStatusColor(status), size: 20),
            ),
            title: Text('${data['fromLocation']} → ${data['toLocation']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${data['fromDistrict'] ?? 'N/A'}, ${data['fromState'] ?? 'N/A'} → ${data['toDistrict'] ?? 'N/A'}, ${data['toState'] ?? 'N/A'}', style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                const SizedBox(height: 4),
                Text('${data['material']} • ₹${data['price']} • ${data['weight'] ?? 'N/A'}'),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _confirmDeleteLoad(loadId),
            ),
          ),
        );
      },
    );
  }

  void _confirmDeleteLoad(String loadId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Load'),
        content: const Text('Are you sure you want to remove this load permanently?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _adminRepo.deleteLoad(loadId);
                _refreshData();
              } catch (e) {
                if (mounted) SnackBarUtils.showError(context, 'Delete failed: $e');

              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildUserList() {
    if (_recentUsers.isEmpty) {
      return _buildEmptyState('No users found');
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _recentUsers.length > 5 ? 5 : _recentUsers.length,
      itemBuilder: (context, index) {
        final data = _recentUsers[index];
        final isBlocked = data['isBlocked'] ?? false;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isBlocked ? Colors.red.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1),
              child: Icon(Icons.person, color: isBlocked ? Colors.red : Colors.blue),
            ),
            title: Text(data['fullName'] ?? data['name'] ?? 'Unknown', style: TextStyle(fontWeight: FontWeight.bold, color: isBlocked ? Colors.grey : Colors.black)),
            subtitle: Text('${data['role']} • ${data['phone']}'),
            trailing: IconButton(
              icon: Icon(isBlocked ? Icons.lock_open : Icons.block, color: isBlocked ? Colors.green : Colors.red),
              onPressed: () => _toggleBlock(data['_id'] ?? data['id'], !isBlocked),
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleBlock(String userId, bool block) async {
    try {
      await _adminRepo.toggleBlockUser(userId, block);
      _refreshData();
    } catch (e) {
      if (mounted) SnackBarUtils.showError(context, 'Update failed: $e');

    }
  }

  Widget _buildBidMonitor() {
    if (_bids.isEmpty) {
      return _buildEmptyState('No pending bids found');
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _bids.length,
      itemBuilder: (context, index) {
        final bid = _bids[index];
        final bidId = bid['_id'] ?? bid['id'];
        final load = bid['loadDetails'] ?? {};
        final driver = bid['driverDetails'] ?? {};
        final bidAmount = bid['bidAmount']?.toString() ?? '0';
        final bidMessage = bid['message'] ?? '';
        final status = (bid['status'] ?? 'Pending').toString();
        
        String timeStr = 'N/A';
        if (bid['createdAt'] != null) {
          try {
            final dt = DateTime.parse(bid['createdAt']);
            timeStr = "${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
          } catch (_) {}
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${load['fromLocation'] ?? 'N/A'} → ${load['toLocation'] ?? 'N/A'}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Bid: ₹$bidAmount',
                        style: const TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Driver: ${driver['name'] ?? 'Unknown'} • Rating: ${driver['rating'] ?? '5.0'} ★',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'Vehicle: ${driver['truckType'] ?? 'N/A'} (${driver['truckNumber'] ?? 'N/A'})',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Load details: ${load['material'] ?? 'N/A'} • ${load['weight'] ?? 'N/A'} • Original Price: ₹${load['price'] ?? '0'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                if (bidMessage.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Message: "$bidMessage"',
                      style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Time: $timeStr', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    if (status == 'Pending')
                      Row(
                        children: [
                          OutlinedButton(
                            onPressed: () => _handleBidAction(bidId, false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                            ),
                            child: const Text('Reject'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => _handleBidAction(bidId, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Accept'),
                          ),
                        ],
                      )
                    else
                      Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: status == 'Accepted' ? Colors.green : Colors.red,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleBidAction(String bidId, bool accept) async {
    setState(() => _isLoading = true);
    try {
      if (accept) {
        await _adminRepo.acceptBid(bidId);
        if (mounted) SnackBarUtils.showSuccess(context, 'Bid accepted successfully!');
      } else {
        await _adminRepo.rejectBid(bidId);
        if (mounted) SnackBarUtils.showSuccess(context, 'Bid rejected successfully!');
      }
      _refreshData();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        SnackBarUtils.showError(context, 'Action failed: $e');
      }
    }
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending': return Colors.orange;
      case 'accepted': return Colors.blue;
      case 'completed': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }
}
