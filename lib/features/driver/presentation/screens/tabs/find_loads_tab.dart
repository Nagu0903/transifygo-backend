import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
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

  @override
  void initState() {
    super.initState();
    context.read<LoadBloc>().add(FetchPendingLoadsRequested());
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
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri.parse('tel:${data['phone']}')),
                    icon: const Icon(Icons.call),
                    label: const Text('Call Owner'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.green, side: const BorderSide(color: Colors.green)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _showAcceptConfirmation(context, loadId),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
                    child: const Text('Accept Load'),
                  ),
                ),
              ],
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

  void _showAcceptConfirmation(BuildContext context, String loadId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accept Load?'),
        content: const Text('Are you sure you want to accept this booking?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final session = await SessionService.getSession();
              if (context.mounted) {
                context.read<LoadBloc>().add(UpdateLoadStatusRequested(
                  loadId, 
                  'accepted', 
                  extraData: {
                    'driverId': session['uid'],
                    'driverName': session['name'],
                    'driverPhone': session['phone'],
                  }
                ));
                Navigator.pop(ctx);
                // Refresh loads
                context.read<LoadBloc>().add(FetchPendingLoadsRequested());
              }
            },
            child: const Text('Accept', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
