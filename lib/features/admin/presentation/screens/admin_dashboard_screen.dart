import 'package:flutter/material.dart';
import 'package:transify_app/features/admin/data/repositories/admin_repository.dart';
import 'package:transify_app/features/auth/presentation/screens/role_selection_screen.dart';
import 'package:transify_app/core/constants/app_colors.dart';
import 'package:transify_app/core/utils/snackbar_utils.dart';


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
      
      if (mounted) {
        setState(() {
          _stats = stats;
          _recentLoads = loads;
          _recentUsers = users;
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
            title: Text(data['name'] ?? 'Unknown', style: TextStyle(fontWeight: FontWeight.bold, color: isBlocked ? Colors.grey : Colors.black)),
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
      default: return Colors.grey;
    }
  }
}
