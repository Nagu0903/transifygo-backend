import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:transify_app/core/constants/app_colors.dart';
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
        backgroundColor: Colors.white,
        body: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeader(lang),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: lang.translate('full_name'),
                        prefixIcon: const Icon(Icons.person_outline, color: AppColors.primaryBlue),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: lang.translate('phone_number'),
                        prefixIcon: const Icon(Icons.phone_android, color: AppColors.primaryBlue),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      keyboardType: isOwner ? TextInputType.number : TextInputType.text,
                      maxLength: isOwner ? 4 : null,
                      decoration: InputDecoration(
                        labelText: isOwner ? lang.translate('pin') : lang.translate('password'),
                        prefixIcon: Icon(isOwner ? Icons.lock_open : Icons.lock_outline, color: AppColors.primaryBlue),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _cityController,
                      decoration: InputDecoration(
                        labelText: lang.translate('village_city'),
                        prefixIcon: const Icon(Icons.location_city_outlined, color: AppColors.primaryBlue),
                      ),
                    ),
                    if (isDriver) ...[
                      const SizedBox(height: 16),
                      _buildVehiclePicker(lang),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _vehicleNumberController,
                        decoration: InputDecoration(
                          labelText: lang.translate('vehicle_number'),
                          prefixIcon: const Icon(Icons.numbers_outlined, color: AppColors.primaryBlue),
                        ),
                      ),
                    ],
                    const SizedBox(height: 40),
                    BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) {
                        return ElevatedButton(
                          onPressed: state is AuthLoading ? null : _onSignup,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 55),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                          child: state is AuthLoading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : Text(lang.translate('signup').toUpperCase(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Already have an account?', style: TextStyle(color: Colors.grey)),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'Login',
                            style: TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(LanguageProvider lang) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 60, bottom: 40, left: 24, right: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryBlue,
            AppColors.primaryBlue.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
          ),
          const SizedBox(height: 20),
          Text(
            'Join TransifyGo',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create account as ${widget.role}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehiclePicker(LanguageProvider lang) {
    final types = ['Tractor', 'Pickup', 'Mini Truck', 'Tempo', 'Lorry', 'Container', 'Trailer'];
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: lang.translate('vehicle_type'),
        prefixIcon: const Icon(Icons.drive_eta_outlined, color: AppColors.primaryBlue),
      ),
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
