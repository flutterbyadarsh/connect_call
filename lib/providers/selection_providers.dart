import 'package:flutter_riverpod/flutter_riverpod.dart';

class SelectionState {
  final bool isSelecting;
  final Set<String> selectedIds;

  SelectionState({this.isSelecting = false, this.selectedIds = const {}});

  SelectionState copyWith({bool? isSelecting, Set<String>? selectedIds}) {
    return SelectionState(
      isSelecting: isSelecting ?? this.isSelecting,
      selectedIds: selectedIds ?? this.selectedIds,
    );
  }
}

class SelectionNotifier extends StateNotifier<SelectionState> {
  SelectionNotifier() : super(SelectionState());

  void toggleSelectionMode() {
    state = state.copyWith(
      isSelecting: !state.isSelecting,
      selectedIds: {}, // Always clear on toggle
    );
  }

  void disableSelectionMode() {
    if (state.isSelecting) {
      state = state.copyWith(isSelecting: false, selectedIds: {});
    }
  }

  void toggleSelection(String id) {
    final currentSet = Set<String>.from(state.selectedIds);
    if (currentSet.contains(id)) {
      currentSet.remove(id);
      if (currentSet.isEmpty) {
        state = state.copyWith(isSelecting: false, selectedIds: {});
      } else {
        state = state.copyWith(selectedIds: currentSet);
      }
    } else {
      currentSet.add(id);
      state = state.copyWith(selectedIds: currentSet);
    }
  }

  void toggleSelectAll(List<String> ids) {
    if (state.selectedIds.length == ids.length) {
      state = state.copyWith(selectedIds: {});
    } else {
      state = state.copyWith(selectedIds: Set.from(ids));
    }
  }

  void clearSelection() {
    state = state.copyWith(selectedIds: {});
  }
}

final callSelectionProvider =
    StateNotifierProvider.autoDispose<SelectionNotifier, SelectionState>((ref) {
      return SelectionNotifier();
    });

final contactSelectionProvider =
    StateNotifierProvider.autoDispose<SelectionNotifier, SelectionState>((ref) {
      return SelectionNotifier();
    });

final chatSelectionProvider =
    StateNotifierProvider.autoDispose<SelectionNotifier, SelectionState>((ref) {
      return SelectionNotifier();
    });
