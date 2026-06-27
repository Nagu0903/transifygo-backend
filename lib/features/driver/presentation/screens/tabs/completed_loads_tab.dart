import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:transify_app/core/constants/app_colors.dart';
import 'package:transify_app/features/load_owner/presentation/bloc/load_bloc.dart';
import 'package:transify_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:transify_app/core/services/notification_service.dart';
import 'dart:async';

class CompletedLoadsTab extends StatefulWidget {
  const CompletedLoadsTab({super.key});

  @override
  State<CompletedLoadsTab> createState() => _CompletedLoadsTabState();
}

class _CompletedLoadsTabState extends State<CompletedLoadsTab> with WidgetsBindingObserver {
  StreamSubscription? _notificationSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchCompletedLoads();
    
    _notificationSub = NotificationService.onNotificationReceived.stream.listen((_) {
      if (mounted) _fetchCompletedLoads();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchCompletedLoads();
    }
  }

  void _fetchCompletedLoads() {
    final driverId = context.read<AuthBloc>().state is AuthAuthenticated 
        ? (context.read<AuthBloc>().state as AuthAuthenticated).uid 
        : null;
    if (driverId != null) {
      context.read<LoadBloc>().add(FetchDriverLoadsRequested(driverId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoadBloc, LoadState>(
      builder: (context, state) {
        if (state is LoadLoading) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primaryBlue));
        }
        
        List<Map<String, dynamic>> completedLoads = [];
        if (state is LoadSuccess && state.loads != null) {
          completedLoads = state.loads!.where((load) => load['status'] == 'completed').toList();
        }

        if (completedLoads.isEmpty) {
          return const Center(child: Text('No completed loads found.'));
        }

        return RefreshIndicator(
          onRefresh: () async => _fetchCompletedLoads(),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: completedLoads.length,
            itemBuilder: (context, index) {
              final data = completedLoads[index];
              return _buildCompletedLoadCard(data);
            },
          ),
        );
      },
    );
  }

  Widget _buildCompletedLoadCard(Map<String, dynamic> data) {
    final String paymentStatus = data['paymentStatus'] ?? 'pending';
    
    Color paymentColor = Colors.red;
    if (paymentStatus == 'paid') paymentColor = Colors.green;
    if (paymentStatus == 'partial') paymentColor = Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 2,
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
                    '${data['fromLocation']} → ${data['toLocation']}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green),
                  ),
                  child: const Text('DELIVERED', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.date_range, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text('Completed: ${_formatDate(data['completedAt'])}', style: const TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Agreed:'),
                      Text('₹${data['totalAmount'] ?? data['price'] ?? '0'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Amount Received:'),
                      Text('₹${data['paidAmount'] ?? '0'}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Remaining Balance:'),
                      Text('₹${data['remainingAmount'] ?? data['price'] ?? '0'}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Payment Status:'),
                      Text(
                        paymentStatus.toUpperCase(), 
                        style: TextStyle(fontWeight: FontWeight.bold, color: paymentColor)
                      ),
                    ],
                  ),
                  if (data['paymentHistory'] != null && (data['paymentHistory'] as List).isNotEmpty) ...[
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Last Payment:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text('₹${(data['paymentHistory'] as List).last['amount']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (data['paymentNotes'] != null && data['paymentNotes'].toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Note: ${data['paymentNotes']}', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
            ]
          ],
        ),
      ),
    );
  }

  String _formatDate(dynamic dateStr) {
    if (dateStr == null) return 'N/A';
    try {
      final dt = DateTime.parse(dateStr.toString()).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return dateStr.toString();
    }
  }
}
