import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:transify_app/features/load_owner/data/repositories/load_repository.dart';

// Events
abstract class LoadEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class PostLoadRequested extends LoadEvent {
  final Map<String, dynamic> loadData;
  PostLoadRequested(this.loadData);
}

class FetchPendingLoadsRequested extends LoadEvent {}

class FetchOwnerLoadsRequested extends LoadEvent {
  final String ownerId;
  FetchOwnerLoadsRequested(this.ownerId);
}

class FetchDriverLoadsRequested extends LoadEvent {
  final String driverId;
  FetchDriverLoadsRequested(this.driverId);
}

class UpdateLoadStatusRequested extends LoadEvent {
  final String loadId;
  final String status;
  final Map<String, dynamic>? extraData;
  UpdateLoadStatusRequested(this.loadId, this.status, {this.extraData});
}

class DeleteLoadRequested extends LoadEvent {
  final String loadId;
  DeleteLoadRequested(this.loadId);
}

class CancelLoadRequested extends LoadEvent {
  final String loadId;
  CancelLoadRequested(this.loadId);
}

// States
abstract class LoadState extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadInitial extends LoadState {}
class LoadLoading extends LoadState {}
class LoadSuccess extends LoadState {
  final String message;
  final List<Map<String, dynamic>>? loads;
  LoadSuccess(this.message, {this.loads});
}
class LoadError extends LoadState {
  final String message;
  LoadError(this.message);
}

// Bloc
class LoadBloc extends Bloc<LoadEvent, LoadState> {
  final LoadRepository _loadRepository = LoadRepository();

  LoadBloc() : super(LoadInitial()) {
    on<PostLoadRequested>(_onPostLoadRequested);
    on<FetchPendingLoadsRequested>(_onFetchPendingLoadsRequested);
    on<FetchOwnerLoadsRequested>(_onFetchOwnerLoadsRequested);
    on<FetchDriverLoadsRequested>(_onFetchDriverLoadsRequested);
    on<UpdateLoadStatusRequested>(_onUpdateLoadStatusRequested);
    on<DeleteLoadRequested>(_onDeleteLoadRequested);
    on<CancelLoadRequested>(_onCancelLoadRequested);
  }

  Future<void> _onPostLoadRequested(PostLoadRequested event, Emitter<LoadState> emit) async {
    emit(LoadLoading());
    try {
      await _loadRepository.postLoad(event.loadData);
      emit(LoadSuccess('Load posted successfully'));
    } catch (e) {
      emit(LoadError(e.toString()));
    }
  }

  Future<void> _onFetchPendingLoadsRequested(FetchPendingLoadsRequested event, Emitter<LoadState> emit) async {
    emit(LoadLoading());
    try {
      final loads = await _loadRepository.fetchPendingLoads();
      emit(LoadSuccess('Loads fetched successfully', loads: loads));
    } catch (e) {
      emit(LoadError(e.toString()));
    }
  }

  Future<void> _onFetchOwnerLoadsRequested(FetchOwnerLoadsRequested event, Emitter<LoadState> emit) async {
    emit(LoadLoading());
    try {
      final loads = await _loadRepository.fetchOwnerLoads(event.ownerId);
      emit(LoadSuccess('Your loads fetched', loads: loads));
    } catch (e) {
      emit(LoadError(e.toString()));
    }
  }

  Future<void> _onFetchDriverLoadsRequested(FetchDriverLoadsRequested event, Emitter<LoadState> emit) async {
    emit(LoadLoading());
    try {
      final loads = await _loadRepository.fetchDriverLoads(event.driverId);
      emit(LoadSuccess('Accepted loads fetched', loads: loads));
    } catch (e) {
      emit(LoadError(e.toString()));
    }
  }

  Future<void> _onUpdateLoadStatusRequested(UpdateLoadStatusRequested event, Emitter<LoadState> emit) async {
    emit(LoadLoading());
    try {
      await _loadRepository.updateLoadStatus(event.loadId, event.status, extraData: event.extraData);
      emit(LoadSuccess('Load ${event.status} successfully'));
    } catch (e) {
      emit(LoadError(e.toString()));
    }
  }

  Future<void> _onDeleteLoadRequested(DeleteLoadRequested event, Emitter<LoadState> emit) async {
    emit(LoadLoading());
    try {
      await _loadRepository.deleteLoad(event.loadId);
      emit(LoadSuccess('Load deleted successfully'));
    } catch (e) {
      emit(LoadError(e.toString()));
    }
  }

  Future<void> _onCancelLoadRequested(CancelLoadRequested event, Emitter<LoadState> emit) async {
    emit(LoadLoading());
    try {
      await _loadRepository.cancelLoad(event.loadId);
      emit(LoadSuccess('LOAD_CANCELLED_SUCCESS'));
    } catch (e) {
      emit(LoadError(e.toString()));
    }
  }
}
