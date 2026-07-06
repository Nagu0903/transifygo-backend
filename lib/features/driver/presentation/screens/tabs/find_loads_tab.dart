import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:transify_app/core/constants/app_colors.dart';
import 'package:transify_app/core/localization/language_provider.dart';
import 'package:transify_app/core/services/session_service.dart';
import 'package:transify_app/features/load_owner/presentation/bloc/load_bloc.dart';

class FindLoadsTab extends StatefulWidget {
  const FindLoadsTab({super.key});

  @override
  State<FindLoadsTab> createState() => _FindLoadsTabState();
}

class _FindLoadsTabState extends State<FindLoadsTab> {
  String _searchQuery = "";

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchPending();
    // Auto refresh every 15 seconds for real-time feel
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (timer) => _fetchPending());
  }

  void _fetchPending() async {
    if (!mounted) return;
    double? lat;
    double? lng;
    try {
      final lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null) {
        lat = lastPos.latitude;
        lng = lastPos.longitude;
      } else {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
          final currentPos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 2),
            ),
          );
          lat = currentPos.latitude;
          lng = currentPos.longitude;
        }
      }
    } catch (e) {
      debugPrint('[DRIVER] Failed to get coordinates for filtering: $e');
    }

    if (mounted) {
      context.read<LoadBloc>().add(FetchPendingLoadsRequested(latitude: lat, longitude: lng));
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search location...',
              prefixIcon: const Icon(Icons.search),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
            ),
          ),
        ),
        Expanded(
          child: BlocListener<LoadBloc, LoadState>(
            listener: (context, state) {
              if (state is LoadSuccess) {
                final msg = state.message.toLowerCase();
                if (msg.contains('accepted') || msg.contains('cancelled') || msg.contains('bid')) {
                  debugPrint('[DRIVER] List change detected or bid placed, refreshing...');
                  _fetchPending();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(state.message), backgroundColor: Colors.green),
                  );
                }
              } else if (state is LoadError) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(state.message), backgroundColor: Colors.red),
                );
              }
            },
            child: BlocBuilder<LoadBloc, LoadState>(
            builder: (context, state) {
              if (state is LoadLoading) return const Center(child: CircularProgressIndicator());
              
              List<Map<String, dynamic>> loads = [];
              if (state is LoadSuccess && state.loads != null) {
                loads = state.loads!;
              }

              var filteredLoads = loads.where((data) {
                if (_searchQuery.isEmpty) return true;
                final from = (data['fromLocation'] ?? '').toString().toLowerCase();
                final to = (data['toLocation'] ?? '').toString().toLowerCase();
                final fromDist = (data['fromDistrict'] ?? '').toString().toLowerCase();
                final toDist = (data['toDistrict'] ?? '').toString().toLowerCase();
                return from.contains(_searchQuery) || to.contains(_searchQuery) || fromDist.contains(_searchQuery) || toDist.contains(_searchQuery);
              }).toList();

              if (filteredLoads.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.search_off, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(lang.translate('no_loads_found')),
                      TextButton(
                        onPressed: () => context.read<LoadBloc>().add(FetchPendingLoadsRequested()),
                        child: Text(lang.translate('refresh')),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  context.read<LoadBloc>().add(FetchPendingLoadsRequested());
                },
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filteredLoads.length,
                  itemBuilder: (context, index) => _buildDriverLoadCard(context, filteredLoads[index]),
                ),
              );
            },
          ),
        ),
      ),
      ],
    );
  }

  Widget _buildDriverLoadCard(BuildContext context, Map<String, dynamic> data) {
    final loadId = data['id'] ?? data['_id'];
    
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
                const Icon(Icons.person, color: Colors.grey, size: 20),
                const SizedBox(width: 8),
                Text(data['fullName'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('₹${data['price'] ?? '0'}', style: const TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            const Divider(height: 32),
            _buildRouteInfo(
              data['fromLocation'] ?? '', 
              data['toLocation'] ?? '', 
              data['fromDistrict'] ?? '',
              data['toDistrict'] ?? '',
              data['distance']?.toString() ?? '0'
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoBadge(Icons.category, data['material'] ?? 'Goods'),
                _buildInfoBadge(Icons.fitness_center, data['weight'] ?? 'N/A'),
                _buildInfoBadge(Icons.local_shipping, data['truckType'] ?? 'Truck'),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showPlaceBidDialog(context, loadId, data),
                icon: const Icon(Icons.gavel),
                label: const Text('Place Bid', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteInfo(String from, String to, String fromDist, String toDist, String distance) {
     return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Column(
          children: [
            Icon(Icons.radio_button_checked, color: Colors.green, size: 20),
            SizedBox(height: 4),
            SizedBox(height: 40, child: VerticalDivider(thickness: 2)),
            SizedBox(height: 4),
            Icon(Icons.location_on, color: Colors.red, size: 20),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(from, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (fromDist.isNotEmpty) Text(fromDist, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              Text(to, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (toDist.isNotEmpty) Text(toDist, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        Text('$distance KM', style: const TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildInfoBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.primaryBlue),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _showPlaceBidDialog(BuildContext context, String loadId, Map<String, dynamic> loadData) {
    final amountController = TextEditingController(text: loadData['price']?.toString() ?? '');
    final messageController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Place Bid', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Bid Amount (₹)',
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter an amount';
                  }
                  if (double.tryParse(val) == null || double.parse(val) <= 0) {
                    return 'Please enter a valid positive amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: messageController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Optional Message',
                  prefixIcon: Icon(Icons.message_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final amount = double.parse(amountController.text.trim());
                final msg = messageController.text.trim();
                final session = await SessionService.getSession();
                
                if (ctx.mounted) {
                  context.read<LoadBloc>().add(PlaceBidRequested(
                    loadId: loadId,
                    driverId: session['uid'] ?? '',
                    bidAmount: amount,
                    message: msg,
                  ));
                  Navigator.pop(ctx);
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
            child: const Text('Submit Bid'),
          ),
        ],
      ),
    );
  }
}
