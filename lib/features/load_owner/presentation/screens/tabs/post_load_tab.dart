import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:google_places_flutter/model/prediction.dart';
import 'package:transify_app/core/constants/api_keys.dart';
import 'package:provider/provider.dart';
import 'package:transify_app/core/constants/app_colors.dart';
import 'package:transify_app/core/localization/language_provider.dart';
import 'package:transify_app/core/services/session_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:transify_app/features/load_owner/presentation/bloc/load_bloc.dart';
import 'dart:math' show cos, sqrt, asin;
import 'package:transify_app/core/utils/snackbar_utils.dart';


class PostLoadTab extends StatefulWidget {
  const PostLoadTab({super.key});

  @override
  State<PostLoadTab> createState() => _PostLoadTabState();
}

class _PostLoadTabState extends State<PostLoadTab> {
  late final TextEditingController _fromController;
  late final TextEditingController _toController;
  late final TextEditingController _weightController;
  late final TextEditingController _amountController;
  late final TextEditingController _notesController;
  
  late final FocusNode _fromFocusNode;
  late final FocusNode _toFocusNode;
  late final FocusNode _weightFocusNode;
  late final FocusNode _amountFocusNode;
  late final FocusNode _notesFocusNode;
  
  String _selectedMaterial = 'Paddy Bags';
  String _selectedVehicle = 'Tractor';
  double _distance = 0.0;
  bool _isGettingLocation = false;
  
  Prediction? _fromPrediction;
  Prediction? _toPrediction;

  final String _googleApiKey = ApiKeys.googleMapsKey;
  final bool _showPlacesError = false;
  
  // Caching for location data to save API quota
  final Map<String, Map<String, dynamic>> _locationCache = {};

  @override
  void initState() {
    super.initState();
    _fromController = TextEditingController();
    _toController = TextEditingController();
    _weightController = TextEditingController();
    _amountController = TextEditingController();
    _notesController = TextEditingController();

    _fromFocusNode = FocusNode();
    _toFocusNode = FocusNode();
    _weightFocusNode = FocusNode();
    _amountFocusNode = FocusNode();
    _notesFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _weightController.dispose();
    _amountController.dispose();
    _notesController.dispose();

    _fromFocusNode.dispose();
    _toFocusNode.dispose();
    _weightFocusNode.dispose();
    _amountFocusNode.dispose();
    _notesFocusNode.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          SnackBarUtils.showWarning(context, 'Location services are disabled. Please enable them.');
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          SnackBarUtils.showError(context, 'Location permissions are permanently denied.');
        }
        return;
      }

      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        Position position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)
        );
        
        String address = "My Current Location";
        String district = "";
        String state = "";

        try {
          List<geo.Placemark> placemarks = await geo.placemarkFromCoordinates(
            position.latitude, 
            position.longitude
          );
          if (placemarks.isNotEmpty) {
            geo.Placemark place = placemarks[0];
            address = "${place.name}, ${place.locality}, ${place.subAdministrativeArea}, ${place.administrativeArea}";
            district = place.subAdministrativeArea ?? "";
            state = place.administrativeArea ?? "";
          }
        } catch (e) {
          debugPrint('Reverse geocoding error: $e');
        }

        setState(() {
          _fromPrediction = Prediction(
            description: address,
            lat: position.latitude.toString(),
            lng: position.longitude.toString(),
          );
          // Store extra data in a way we can access later
          _locationCache[address] = {
            'district': district,
            'state': state,
            'lat': position.latitude,
            'lng': position.longitude,
          };
          _fromController.text = address;
          _calculateDistance();
        });
      }
    } catch (e) {
      debugPrint('Location error: $e');
      if (mounted) {
        SnackBarUtils.showError(context, 'Error getting location: $e');
      }
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  void _calculateDistance() {
    if (_fromPrediction != null && _toPrediction != null) {
      try {
        double lat1 = double.parse(_fromPrediction!.lat!);
        double lon1 = double.parse(_fromPrediction!.lng!);
        double lat2 = double.parse(_toPrediction!.lat!);
        double lon2 = double.parse(_toPrediction!.lng!);

        var p = 0.017453292519943295;
        var c = cos;
        var a = 0.5 - c((lat2 - lat1) * p) / 2 +
            c(lat1 * p) * c(lat2 * p) *
                (1 - c((lon2 - lon1) * p)) / 2;
        
        setState(() {
          _distance = 12742 * asin(sqrt(a));
          _distance = _distance * 1.2; // Approximation for road turns
        });
      } catch (e) {
        debugPrint('Distance calculation error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return BlocListener<LoadBloc, LoadState>(
      listener: (context, state) {
        if (state is LoadSuccess) {
          SnackBarUtils.showSuccess(context, state.message);
          _clearForm();
        } else if (state is LoadError) {
          SnackBarUtils.showError(context, state.message);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(lang.translate('post_load'))),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildLocationSearch(
                        lang: lang,
                        labelKey: 'from',
                        controller: _fromController,
                        focusNode: _fromFocusNode,
                        nextFocusNode: _toFocusNode,
                        onSelected: (p) {
                          _fromPrediction = p;
                          _calculateDistance();
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: () => _manualSearch(_fromController, (p) {
                        _fromPrediction = p;
                        _calculateDistance();
                      }),
                      icon: const Icon(Icons.search, color: Colors.grey, size: 20),
                      tooltip: 'Manual Search Fallback',
                    ),
                    IconButton(
                      onPressed: _isGettingLocation ? null : _getCurrentLocation,
                      icon: _isGettingLocation 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location, color: AppColors.primaryBlue),
                      tooltip: 'Use Current Location',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildLocationSearch(
                        lang: lang,
                        labelKey: 'to',
                        controller: _toController,
                        focusNode: _toFocusNode,
                        nextFocusNode: _weightFocusNode,
                        onSelected: (p) {
                          _toPrediction = p;
                          _calculateDistance();
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: () => _manualSearch(_toController, (p) {
                        _toPrediction = p;
                        _calculateDistance();
                      }),
                      icon: const Icon(Icons.search, color: Colors.grey, size: 20),
                      tooltip: 'Manual Search Fallback',
                    ),
                  ],
                ),
                if (_showPlacesError)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Location service temporarily unavailable. Use 🔍 for manual search.',
                      style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                const SizedBox(height: 8),
                if (_distance > 0)
                  _buildDistanceBadge(),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _buildDropdown(
                        lang, 
                        'material_type', 
                        ['Paddy Bags', 'Rice Bags', 'Cement', 'Steel', 'Fruits', 'Vegetables', 'Machinery', 'Fertilizer', 'Custom'], 
                        (val) => setState(() => _selectedMaterial = val!)
                      )
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        lang: lang, 
                        labelKey: 'weight', 
                        controller: _weightController, 
                        focusNode: _weightFocusNode,
                        nextFocusNode: _amountFocusNode,
                        type: TextInputType.number,
                        action: TextInputAction.next,
                      )
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildDropdown(
                  lang, 
                  'vehicle_type', 
                  ['Tractor', 'Pickup', 'Mini Truck', 'Tempo', 'Lorry', 'Container', 'Trailer'], 
                  (val) => setState(() => _selectedVehicle = val!)
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  lang: lang, 
                  labelKey: 'load_amount', 
                  controller: _amountController, 
                  focusNode: _amountFocusNode,
                  nextFocusNode: _notesFocusNode,
                  type: TextInputType.number,
                  prefix: '₹',
                  action: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  lang: lang, 
                  labelKey: 'notes', 
                  controller: _notesController, 
                  focusNode: _notesFocusNode,
                  type: TextInputType.multiline, 
                  maxLines: 3,
                  action: TextInputAction.done,
                ),
                const SizedBox(height: 32),
                _buildSubmitButton(lang),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDistanceBadge() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.1), 
        borderRadius: BorderRadius.circular(12)
      ),
      child: Row(
        children: [
          const Icon(Icons.route, color: AppColors.primaryBlue),
          const SizedBox(width: 12),
          Text(
            'Estimated Distance: ${_distance.toStringAsFixed(1)} KM', 
            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryBlue)
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton(LanguageProvider lang) {
    return BlocBuilder<LoadBloc, LoadState>(
      builder: (context, state) {
        return ElevatedButton(
          onPressed: state is LoadLoading ? null : _submitLoad,
          style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
          child: state is LoadLoading 
              ? const CircularProgressIndicator(color: Colors.white) 
              : Text(lang.translate('post_load')),
        );
      },
    );
  }

  Widget _buildLocationSearch({
    required LanguageProvider lang, 
    required String labelKey, 
    required TextEditingController controller, 
    required FocusNode focusNode,
    FocusNode? nextFocusNode,
    required Function(Prediction) onSelected,
  }) {
    return GooglePlaceAutoCompleteTextField(
      textEditingController: controller,
      googleAPIKey: _googleApiKey,
      inputDecoration: InputDecoration(
        labelText: lang.translate(labelKey),
        prefixIcon: const Icon(Icons.location_on, color: AppColors.primaryOrange),
        suffixIcon: controller.text.isNotEmpty 
            ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() => controller.clear()))
            : null,
      ),
      focusNode: focusNode,
      debounceTime: 800,
      countries: ["in"],
      itemClick: (Prediction prediction) async {
        controller.text = prediction.description ?? "";
        controller.selection = TextSelection.fromPosition(TextPosition(offset: prediction.description?.length ?? 0));
        
        final desc = prediction.description ?? "";
        
        // Check cache first
        if (!_locationCache.containsKey(desc)) {
          try {
            List<geo.Location> locations = await geo.locationFromAddress(desc);
            if (locations.isNotEmpty) {
              prediction.lat = locations[0].latitude.toString();
              prediction.lng = locations[0].longitude.toString();
              
              // Get District and State
              List<geo.Placemark> placemarks = await geo.placemarkFromCoordinates(
                locations[0].latitude, 
                locations[0].longitude
              );
              
              if (placemarks.isNotEmpty) {
                final p = placemarks[0];
                _locationCache[desc] = {
                  'district': p.subAdministrativeArea ?? p.locality ?? "",
                  'state': p.administrativeArea ?? "",
                  'lat': locations[0].latitude,
                  'lng': locations[0].longitude,
                };
              }
            }
          } catch (e) {
            debugPrint('Error fetching location details: $e');
          }
        }

        if (prediction.lat == null && _locationCache.containsKey(desc)) {
          prediction.lat = _locationCache[desc]!['lat'].toString();
          prediction.lng = _locationCache[desc]!['lng'].toString();
        }

        onSelected(prediction);
        if (nextFocusNode != null) {
          nextFocusNode.requestFocus();
        } else {
          focusNode.unfocus();
        }
      },
      itemBuilder: (context, index, Prediction prediction) {
        return Container(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const Icon(Icons.location_on, size: 16, color: Colors.grey), 
            const SizedBox(width: 12), 
            Expanded(child: Text(prediction.description ?? "", style: const TextStyle(fontSize: 14)))
          ]),
        );
      },
      seperatedBuilder: const Divider(height: 1),
    );
  }

  Future<void> _manualSearch(TextEditingController controller, Function(Prediction) onSelected) async {
    final query = controller.text.trim();
    if (query.isEmpty) return;

    setState(() => _isGettingLocation = true);
    try {
      List<geo.Location> locations = await geo.locationFromAddress(query);
      if (locations.isNotEmpty) {
        final loc = locations[0];
        
        // Get details
        List<geo.Placemark> placemarks = await geo.placemarkFromCoordinates(loc.latitude, loc.longitude);
        String fullAddress = query;
        String district = "";
        String state = "";

        if (placemarks.isNotEmpty) {
          final p = placemarks[0];
          fullAddress = "${p.name}, ${p.locality}, ${p.subAdministrativeArea}, ${p.administrativeArea}";
          district = p.subAdministrativeArea ?? p.locality ?? "";
          state = p.administrativeArea ?? "";
        }

        final prediction = Prediction(
          description: fullAddress,
          lat: loc.latitude.toString(),
          lng: loc.longitude.toString(),
        );

        _locationCache[fullAddress] = {
          'district': district,
          'state': state,
          'lat': loc.latitude,
          'lng': loc.longitude,
        };

        controller.text = fullAddress;
        onSelected(prediction);
        
        if (mounted) {
          SnackBarUtils.showSuccess(context, 'Location found via manual search');
        }
      } else {
        throw 'No locations found for "$query"';
      }
    } catch (e) {
      debugPrint('Manual search error: $e');
      if (mounted) {
        SnackBarUtils.showWarning(context, 'Could not find location. Try adding city/district name.');
      }
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  Widget _buildTextField({
    required LanguageProvider lang, 
    required String labelKey, 
    required TextEditingController controller, 
    required FocusNode focusNode,
    FocusNode? nextFocusNode,
    required TextInputType type, 
    TextInputAction action = TextInputAction.next,
    String? prefix, 
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: type,
      textInputAction: action,
      maxLines: maxLines,
      onSubmitted: (_) {
        if (nextFocusNode != null) {
          nextFocusNode.requestFocus();
        } else {
          focusNode.unfocus();
        }
      },
      decoration: InputDecoration(
        labelText: lang.translate(labelKey),
        prefixText: prefix,
      ),
    );
  }

  Widget _buildDropdown(LanguageProvider lang, String labelKey, List<String> items, Function(String?) onChanged) {
    return DropdownButtonFormField<String>(
      initialValue: labelKey == 'material_type' ? _selectedMaterial : _selectedVehicle,
      decoration: InputDecoration(labelText: lang.translate(labelKey)),
      items: items.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
      onChanged: (val) {
        FocusScope.of(context).unfocus();
        onChanged(val);
      },
    );
  }

  void _submitLoad() async {
    final from = _fromController.text.trim();
    final to = _toController.text.trim();
    final weight = _weightController.text.trim();
    final amount = _amountController.text.trim();

    if (from.isEmpty || to.isEmpty || weight.isEmpty || amount.isEmpty) {
      SnackBarUtils.showWarning(context, 'Please fill all required fields');
      return;
    }

    final session = await SessionService.getSession();
    if (!mounted) return;
    
    final uid = session['uid'];
    final name = session['name'];
    final phone = session['phone'];

    final fromDesc = _fromController.text.trim();
    final toDesc = _toController.text.trim();
    
    final fromData = _locationCache[fromDesc] ?? {};
    final toData = _locationCache[toDesc] ?? {};

    context.read<LoadBloc>().add(PostLoadRequested({
      'userId': uid,
      'fullName': name,
      'phone': phone,
      'fromLocation': from,
      'fromDistrict': fromData['district'] ?? "",
      'fromState': fromData['state'] ?? "",
      'fromLat': fromData['lat'],
      'fromLng': fromData['lng'],
      'toLocation': to,
      'toDistrict': toData['district'] ?? "",
      'toState': toData['state'] ?? "",
      'toLat': toData['lat'],
      'toLng': toData['lng'],
      'material': _selectedMaterial,
      'weight': weight,
      'truckType': _selectedVehicle,
      'price': amount,
      'notes': _notesController.text.trim(),
      'distance': _distance.toStringAsFixed(1),
    }));
  }

  void _clearForm() {
    _fromController.clear();
    _toController.clear();
    _weightController.clear();
    _amountController.clear();
    _notesController.clear();
    setState(() {
      _distance = 0.0;
      _fromPrediction = null;
      _toPrediction = null;
    });
  }
}
