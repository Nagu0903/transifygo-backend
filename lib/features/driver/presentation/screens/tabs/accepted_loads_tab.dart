import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:transify_app/core/constants/app_colors.dart';
import 'package:transify_app/core/services/session_service.dart';
import 'package:transify_app/core/services/tracking_service.dart';
import 'package:transify_app/features/load_owner/presentation/bloc/load_bloc.dart';
import 'package:transify_app/features/driver/presentation/screens/tabs/complete_load_sheet.dart' as transify_complete_sheet;

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
    return BlocListener<LoadBloc, LoadState>(
      listener: (context, state) {
        if (state is LoadSuccess) {
          final msg = state.message.toLowerCase();
          // Listen for any cancellation or success event to trigger a refresh
          if (msg.contains('success') || msg.contains('cancelled')) {
             debugPrint('[DRIVER] List sync detected, refreshing accepted loads...');
             _fetchLoads();
          }
        }
      },
      child: BlocBuilder<LoadBloc, LoadState>(
      builder: (context, state) {
        if (state is LoadLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        List<Map<String, dynamic>> loads = [];
        if (state is LoadSuccess && state.loads != null) {
          loads = state.loads!.where((load) => load['status'] != 'completed' && load['status'] != 'cancelled').toList();
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
    ),
    );
  }

  void _showCompleteLoadSheet(BuildContext context, String loadId) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => transify_complete_sheet.CompleteLoadSheet(loadId: loadId),
    );

    if (result == true) {
      await TrackingService().stopTracking(loadId);
      // Refresh the list if completion was successful
      _fetchLoads();
    }
  }

  void _toggleTripTracking(Map<String, dynamic> data) async {
    final loadId = data['_id'];
    final driverId = data['driverId'] ?? '';
    final tracking = TrackingService();

    if (tracking.isRunning && tracking.activeLoadId == loadId) {
      await tracking.stopTracking(loadId);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip tracking stopped successfully.')),
        );
      }
    } else {
      final consent = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Row(
            children: [
              Icon(Icons.location_on, color: AppColors.primaryBlue),
              SizedBox(width: 8),
              Text('Location Access Consent', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'TransifyGo collects real-time location data to allow the load owner to monitor the transit status of their shipment.\n\n'
            'This data will be gathered in the background (even when the app is minimized or closed) during active trips, and will only be shared with the load owner.\n\n'
            'Do you agree to start live GPS tracking for this trip?',
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Agree & Start Trip'),
            ),
          ],
        ),
      );

      if (consent == true) {
        final ownerId = data['userId'] ?? '';
        final started = await tracking.startTracking(loadId, driverId, ownerId);
        if (mounted) {
          setState(() {});
          if (started) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Trip started! Live tracking is active.')),
            );
          } else {
            final errorMsg = TrackingService.lastError ?? 'Failed to start trip. Please enable location services and try again.';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMsg),
                backgroundColor: Colors.red.shade900,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      }
    }
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
            
            // Trip Tracking Controls
            Builder(
              builder: (context) {
                final tracking = TrackingService();
                final isCurrentTripTracking = tracking.isRunning && tracking.activeLoadId == data['_id'];
                final isAnotherTripTracking = tracking.isRunning && tracking.activeLoadId != data['_id'];

                if (isCurrentTripTracking) {
                  return Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _toggleTripTracking(data),
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop Trip', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
                } else if (isAnotherTripTracking) {
                  return Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.navigation),
                          label: const Text('Start Trip (Other Trip Active)', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _toggleTripTracking(data),
                          icon: const Icon(Icons.navigation),
                          label: const Text('Start Trip', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
                }
              },
            ),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri.parse('tel:${data['phone']}')),
                    icon: const Icon(Icons.call, size: 18),
                    label: const Text('Call Owner'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green,
                      side: const BorderSide(color: Colors.green),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showCompleteLoadSheet(context, data['_id']),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Complete'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
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
