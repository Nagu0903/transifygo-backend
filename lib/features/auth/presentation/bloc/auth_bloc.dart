import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:transify_app/core/services/session_service.dart';
import 'package:transify_app/core/services/notification_service.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/models/user_model.dart';

// Events
abstract class AuthEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoginRequested extends AuthEvent {
  final String phone;
  final String password;
  final String role;
  LoginRequested(this.phone, this.password, this.role);
}

class SignupRequested extends AuthEvent {
  final String name;
  final String phone;
  final String password;
  final String role;
  final String city;
  final Map<String, dynamic>? extraData;
  SignupRequested({required this.name, required this.phone, required this.password, required this.role, required this.city, this.extraData});
}

class LogoutRequested extends AuthEvent {}

class ResetPasswordRequested extends AuthEvent {
  final String phone;
  final String role;
  final String newPassword;
  ResetPasswordRequested({required this.phone, required this.role, required this.newPassword});
}

// States
abstract class AuthState extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}
class AuthLoading extends AuthState {}
class AuthAuthenticated extends AuthState {
  final String role;
  final String uid;
  AuthAuthenticated({required this.role, required this.uid});

  @override
  List<Object?> get props => [role, uid];
}
class AuthUnauthenticated extends AuthState {}
class AuthError extends AuthState {
  final String message;
  AuthError(this.message);

  @override
  List<Object?> get props => [message];
}

// Bloc
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository = AuthRepository();

  AuthBloc() : super(AuthInitial()) {
    on<LoginRequested>(_onLoginRequested);
    on<SignupRequested>(_onSignupRequested);
    on<LogoutRequested>(_onLogoutRequested);
    on<ResetPasswordRequested>(_onResetPasswordRequested);
  }

  Future<void> _onLoginRequested(LoginRequested event, Emitter<AuthState> emit) async {
    if (event.phone.isEmpty || event.password.isEmpty) {
      emit(AuthError('Please enter phone and password'));
      return;
    }

    emit(AuthLoading());
    try {
      final user = await _authRepository.login(event.phone, event.password, event.role);

      if (user == null) {
        emit(AuthError('Invalid phone or password'));
      } else if (user.isBlocked) {
        emit(AuthError('Your account has been blocked'));
      } else {
        await SessionService.saveSession(
          uid: user.id!,
          role: user.role,
          name: user.name,
          phone: user.phone,
          fullName: user.fullName,
        );
        
        // Update notification token
        await NotificationService.updateToken();

        emit(AuthAuthenticated(role: user.role, uid: user.id!));
      }
    } catch (e) {
      // Professional error handling for different scenarios
      String errorMsg = e.toString();
      if (errorMsg.contains('timed out')) {
        errorMsg = 'Connection Timeout: Please check your internet or server.';
      } else if (errorMsg.contains('Network error')) {
        errorMsg = 'Network Error: Cannot connect to server.';
      }
      emit(AuthError(errorMsg));
    } finally {
      // Ensure loading state is never stuck
      if (state is AuthLoading) {
        emit(AuthInitial()); 
      }
    }
  }

  Future<void> _onSignupRequested(SignupRequested event, Emitter<AuthState> emit) async {
    if (event.name.isEmpty || event.phone.isEmpty || event.password.isEmpty || event.city.isEmpty) {
      emit(AuthError('Please fill all required fields'));
      return;
    }

    emit(AuthLoading());
    try {
      // Signup in Repository
      final createdUser = await _authRepository.signup(UserModel(
        name: event.name,
        phone: event.phone,
        password: event.password,
        role: event.role,
        city: event.city,
        truckType: event.extraData?['vehicleType'],
        truckNumber: event.extraData?['vehicleNumber'],
      ));

      // Save session
      await SessionService.saveSession(
        uid: createdUser.id!,
        role: createdUser.role,
        name: createdUser.name,
        phone: createdUser.phone,
        fullName: createdUser.fullName,
      );

      // Update notification token
      await NotificationService.updateToken();

      emit(AuthAuthenticated(role: createdUser.role, uid: createdUser.id!));
    } catch (e) {
      emit(AuthError('Signup failed: ${e.toString()}'));
    } finally {
      // Ensure loader stops
      if (state is AuthLoading) {
        emit(AuthInitial());
      }
    }
  }

  Future<void> _onLogoutRequested(LogoutRequested event, Emitter<AuthState> emit) async {
    await SessionService.clearSession();
    emit(AuthUnauthenticated());
  }

  Future<void> _onResetPasswordRequested(ResetPasswordRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final success = await _authRepository.resetPassword(event.phone, event.role, event.newPassword);
      if (success) {
        emit(AuthInitial()); // Reset to initial so user can login
      } else {
        emit(AuthError('Failed to reset password'));
      }
    } catch (e) {
      emit(AuthError(e.toString()));
    } finally {
      if (state is AuthLoading) {
        emit(AuthInitial());
      }
    }
  }
}
