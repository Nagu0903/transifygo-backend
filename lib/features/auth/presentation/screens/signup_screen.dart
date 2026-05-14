import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:transify_app/core/localization/language_provider.dart';
import 'package:transify_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:transify_app/features/load_owner/presentation/screens/owner_dashboard_screen.dart';
import 'package:transify_app/features/driver/presentation/screens/driver_dashboard_screen.dart';
import 'package:transify_app/core/utils/snackbar_utils.dart';



class SignupScreen extends StatefulWidget {
  final String role;
  const SignupScreen({super.key, required this.role});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _cityController = TextEditingController();
  final _vehicleTypeController = TextEditingController(); // For drivers
  final _vehicleNumberController = TextEditingController(); // For drivers

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final isDriver = widget.role == 'Driver';
    final isOwner = widget.role == 'Load Owner';

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          SnackBarUtils.showSuccess(context, 'Signup successful!');
          if (state.role == 'Load Owner') {
            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const OwnerDashboardScreen()), (route) => false);
          } else if (state.role == 'Driver') {
            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const DriverDashboardScreen()), (route) => false);
          }
        } else if (state is AuthError) {
          SnackBarUtils.showError(context, state.message);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text('${lang.translate('signup')} - ${lang.translate(widget.role.toLowerCase().replaceAll(' ', '_'))}')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(labelText: lang.translate('full_name'), prefixIcon: const Icon(Icons.person)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: lang.translate('phone_number'), prefixIcon: const Icon(Icons.phone)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                keyboardType: isOwner ? TextInputType.number : TextInputType.text,
                maxLength: isOwner ? 4 : null,
                decoration: InputDecoration(
                  labelText: isOwner ? lang.translate('pin') : lang.translate('password'),
                  prefixIcon: const Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _cityController,
                decoration: InputDecoration(labelText: lang.translate('village_city'), prefixIcon: const Icon(Icons.location_city)),
              ),
              if (isDriver) ...[
                const SizedBox(height: 16),
                _buildVehiclePicker(lang),
                const SizedBox(height: 16),
                TextField(
                  controller: _vehicleNumberController,
                  decoration: InputDecoration(labelText: lang.translate('vehicle_number'), prefixIcon: const Icon(Icons.numbers)),
                ),
              ],
              const SizedBox(height: 40),
              BlocBuilder<AuthBloc, AuthState>(
                builder: (context, state) {
                  return ElevatedButton(
                    onPressed: state is AuthLoading ? null : _onSignup,
                    child: state is AuthLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(lang.translate('signup')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVehiclePicker(LanguageProvider lang) {
    final types = ['Tractor', 'Pickup', 'Mini Truck', 'Tempo', 'Lorry', 'Container', 'Trailer'];
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(labelText: lang.translate('vehicle_type'), prefixIcon: const Icon(Icons.drive_eta)),
      items: types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
      onChanged: (val) => _vehicleTypeController.text = val ?? '',
    );
  }

  void _onSignup() {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();
    final city = _cityController.text.trim();

    if (name.isEmpty || phone.isEmpty || password.isEmpty || city.isEmpty) {
      SnackBarUtils.showWarning(context, 'Please fill all fields');
      return;
    }

    if (widget.role == 'Load Owner' && password.length != 4) {
      SnackBarUtils.showWarning(context, 'PIN must be 4 digits');
      return;
    }

    Map<String, dynamic>? extra;
    if (widget.role == 'Driver') {
      extra = {
        'vehicleType': _vehicleTypeController.text,
        'vehicleNumber': _vehicleNumberController.text,
      };
    }

    context.read<AuthBloc>().add(SignupRequested(
      name: name,
      phone: phone,
      password: password,
      role: widget.role,
      city: city,
      extraData: extra,
    ));
  }
}
