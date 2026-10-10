import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/state_views.dart';

Widget coordinatorAsyncState<T>({
  required AsyncValue<T> value,
  required Widget Function(T data) data,
  required VoidCallback retry,
}) {
  return value.when(
    loading: () => const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    ),
    error: (error, stackTrace) => ErrorState(
      message: error.toString(),
      onRetry: retry,
    ),
    data: data,
  );
}
