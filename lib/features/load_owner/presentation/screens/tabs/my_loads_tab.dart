import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:transify_app/core/constants/app_colors.dart';
import 'package:transify_app/core/localization/language_provider.dart';
import 'package:transify_app/core/services/session_service.dart';
import 'package:transify_app/features/load_owner/presentation/bloc/load_bloc.dart';

class MyLoadsTab extends StatefulWidget {
  const MyLoadsTab({super.key});

  @override
  State<MyLoadsTab> createState() => _MyLoadsTabState();
}

class _MyLoadsTabState extends State<MyLoadsTab> {
  String? _userId;

  @override
  void initState() {
    super.initState();
    _loadUserAndFetch();
  }

  Future<void> _loadUserAndFetch() async {
    final session = await SessionService.getSession();
    if (mounted) {
      setState(() => _userId = session['uid']);
      _fetchLoads();
    }
  }

  void _fetchLoads() {
    if (_userId != null) {
      context.read<LoadBloc>().add(FetchOwnerLoadsRequested(_userId!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(lang.translate('my_loads')),
          bottom: TabBar(
            tabs: [
              Tab(text: lang.translate('pending')),
              Tab(text: lang.translate('accepted')),
              Tab(text: lang.translate('completed')),
              Tab(text: 'Cancelled'),
            ],
            labelColor: AppColors.primaryBlue,
            indicatorColor: AppColors.primaryBlue,
          ),
        ),
        body: _userId == null 
          ? const Center(child: CircularProgressIndicator())
          : BlocListener<LoadBloc, LoadState>(
              listener: (context, state) {
                if (state is LoadSuccess) {
                  final msg = state.message.toLowerCase();
                  if (msg.contains('cancelled') || msg.contains('completed') || msg.contains('accepted') || msg.contains('success')) {
                    debugPrint('[UI] Status update detected, refreshing list...');
                    _fetchLoads();
                  }
                }
              },
              child: BlocBuilder<LoadBloc, LoadState>(
                builder: (context, state) {
                  if (state is LoadLoading) return const Center(child: CircularProgressIndicator());
                  
                  List<Map<String, dynamic>> allLoads = [];
                  if (state is LoadSuccess && state.loads != null) {
                    allLoads = state.loads!;
                  }

                  return TabBarView(
                    children: [
                      _buildStatusList(context, allLoads, 'pending'),
                      _buildStatusList(context, allLoads, 'accepted'),
                      _buildStatusList(context, allLoads, 'completed'),
                      _buildStatusList(context, allLoads, 'cancelled'),
                    ],
                  );
                },
              ),
            ),
      ),
    );
  }

  Widget _buildStatusList(BuildContext context, List<Map<String, dynamic>> loads, String status) {
    final filtered = loads.where((l) => l['status'] == status).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('No ${status.toUpperCase()} loads found', style: const TextStyle(color: Colors.grey)),
            TextButton(onPressed: _fetchLoads, child: const Text('Refresh')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _fetchLoads(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filtered.length,
        itemBuilder: (context, index) => _buildLoadCard(context, filtered[index]),
      ),
    );
  }

  Widget _buildLoadCard(BuildContext context, Map<String, dynamic> data) {
    final loadId = data['id'] ?? data['_id'];

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
                _buildStatusBadge(data['status']),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${data['fromDistrict'] ?? 'N/A'}, ${data['fromState'] ?? 'N/A'} → ${data['toDistrict'] ?? 'N/A'}, ${data['toState'] ?? 'N/A'}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
            ),
            const Divider(height: 24),
            Row(
              children: [
                _buildInfoItem(Icons.category, data['material']),
                _buildInfoItem(Icons.fitness_center, data['weight'] ?? 'N/A'),
                _buildInfoItem(Icons.route, '${data['distance'] ?? '0'} KM'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildInfoItem(Icons.drive_eta, data['truckType']),
                _buildInfoItem(Icons.payments, '₹${data['price']}', color: AppColors.primaryBlue),
              ],
            ),
            if (data['status'] == 'accepted' && data['driverPhone'] != null) ...[
              const Divider(height: 24),
              Row(
                children: [
                  const Icon(Icons.person, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text('Driver: ${data['driverName']}', style: const TextStyle(fontWeight: FontWeight.w500)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => launchUrl(Uri.parse('tel:${data['driverPhone']}')),
                    icon: const Icon(Icons.call, color: Colors.green),
                    style: IconButton.styleFrom(backgroundColor: Colors.green.withValues(alpha: 0.1)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _updateStatus(context, loadId, 'completed'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('Mark as Delivered'),
                ),
              ),
            ],
            if (data['status'] == 'pending') ...[
              const Divider(height: 24),
              TextButton.icon(
                onPressed: () => _cancelLoad(context, loadId),
                icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                label: const Text('Cancel Load', style: TextStyle(color: Colors.red)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    switch (status) {
      case 'pending': color = Colors.orange; break;
      case 'accepted': color = Colors.blue; break;
      case 'completed': color = Colors.green; break;
      case 'cancelled': color = Colors.red; break;
      default: color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(status.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10)),
    );
  }

  Widget _buildInfoItem(IconData icon, String text, {Color? color}) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 14, color: color ?? Colors.grey),
          const SizedBox(width: 4),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: color != null ? FontWeight.bold : null), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  void _updateStatus(BuildContext context, String loadId, String status) {
    context.read<LoadBloc>().add(UpdateLoadStatusRequested(loadId, status));
    // Wait a bit and refresh
    Future.delayed(const Duration(milliseconds: 500), _fetchLoads);
  }

  void _cancelLoad(BuildContext context, String loadId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Load'),
        content: const Text('Are you sure you want to cancel this load? It will be moved to the Cancelled tab.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('No')),
          TextButton(
            onPressed: () {
              context.read<LoadBloc>().add(CancelLoadRequested(loadId));
              Navigator.pop(ctx);
              _fetchLoads();
            },
            child: const Text('Yes, Cancel', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
