import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:transify_app/core/constants/app_colors.dart';
import 'package:transify_app/core/services/session_service.dart';
import 'package:transify_app/features/load_owner/presentation/bloc/load_bloc.dart';

class AcceptedLoadsTab extends StatefulWidget {
  const AcceptedLoadsTab({super.key});

  @override
  State<AcceptedLoadsTab> createState() => _AcceptedLoadsTabState();
}

class _AcceptedLoadsTabState extends State<AcceptedLoadsTab> {
  @override
  void initState() {
    super.initState();
    _fetchLoads();
  }

  Future<void> _fetchLoads() async {
    final session = await SessionService.getSession();
    if (mounted) {
      context.read<LoadBloc>().add(FetchDriverLoadsRequested(session['uid']!));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoadBloc, LoadState>(
      builder: (context, state) {
        if (state is LoadLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        List<Map<String, dynamic>> loads = [];
        if (state is LoadSuccess && state.loads != null) {
          loads = state.loads!;
        }

        if (loads.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.assignment_turned_in_outlined, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                const Text(
                  'No accepted loads yet',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
                TextButton(
                  onPressed: _fetchLoads,
                  child: const Text('Refresh'),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _fetchLoads,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: loads.length,
            itemBuilder: (context, index) => _buildAcceptedLoadCard(context, loads[index]),
          ),
        );
      },
    );
  }

  Widget _buildAcceptedLoadCard(BuildContext context, Map<String, dynamic> data) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'ACCEPTED',
                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                const Spacer(),
                Text('₹${data['price']}', style: const TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            const Divider(height: 32),
            _buildRouteInfo(data['fromLocation'], data['toLocation'], data['distance']?.toString() ?? '0'),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildDetailItem(Icons.category, data['material']),
                _buildDetailItem(Icons.fitness_center, data['weight'] ?? 'N/A'),
                _buildDetailItem(Icons.person, data['fullName']),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => launchUrl(Uri.parse('tel:${data['phone']}')),
                icon: const Icon(Icons.call),
                label: const Text('Call Owner to Coordinate'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteInfo(String from, String to, String distance) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Column(
          children: [
            Icon(Icons.radio_button_checked, color: Colors.green, size: 20),
            SizedBox(height: 4),
            SizedBox(height: 20, child: VerticalDivider(thickness: 2)),
            SizedBox(height: 4),
            Icon(Icons.location_on, color: Colors.red, size: 20),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(from, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
              const SizedBox(height: 24),
              Text(to, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
            ],
          ),
        ),
        Text('$distance KM', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildDetailItem(IconData icon, String text) {
    return Column(
      children: [
        Icon(icon, size: 18, color: AppColors.primaryBlue.withValues(alpha: 0.7)),
        const SizedBox(height: 4),
        Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
