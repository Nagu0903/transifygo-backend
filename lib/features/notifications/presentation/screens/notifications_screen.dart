import 'package:flutter/material.dart';
import 'package:transify_app/core/constants/app_colors.dart';
import 'package:transify_app/core/network/api_service.dart';
import 'package:transify_app/core/services/session_service.dart';
import 'package:intl/intl.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  List<dynamic> _notifications = [];

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    setState(() => _isLoading = true);
    try {
      final session = await SessionService.getSession();
      final uid = session['uid'];
      if (uid != null) {
        final response = await _api.get('/notifications/$uid');
        if (response.data['success']) {
          setState(() {
            _notifications = response.data['notifications'];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(onPressed: _fetchNotifications, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _fetchNotifications,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      final item = _notifications[index];
                      return _buildNotificationCard(item);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_outlined, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text('No notifications yet', style: TextStyle(color: Colors.grey, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(dynamic item) {
    final type = item['type'] ?? 'info';
    final date = DateTime.parse(item['createdAt'] ?? DateTime.now().toString());
    final isRead = item['isRead'] ?? false;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: isRead ? Colors.white : AppColors.primaryBlue.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: _getTypeColor(type).withValues(alpha: 0.1),
          child: Icon(_getTypeIcon(type), color: _getTypeColor(type), size: 20),
        ),
        title: Text(
          item['title'] ?? 'Notification',
          style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(item['body'] ?? ''),
            const SizedBox(height: 8),
            Text(
              DateFormat('dd MMM, hh:mm a').format(date),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
        onTap: () {
          if (!isRead) {
            _api.put('/notifications/read/${item['_id']}', {});
            setState(() => item['isRead'] = true);
          }
        },
      ),
    );
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'new_load': return Icons.local_shipping;
      case 'load_accepted': return Icons.check_circle;
      case 'load_cancelled': return Icons.cancel;
      case 'load_completed': return Icons.stars;
      default: return Icons.notifications;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'new_load': return Colors.blue;
      case 'load_accepted': return Colors.green;
      case 'load_cancelled': return Colors.red;
      case 'load_completed': return Colors.orange;
      default: return AppColors.primaryBlue;
    }
  }
}
