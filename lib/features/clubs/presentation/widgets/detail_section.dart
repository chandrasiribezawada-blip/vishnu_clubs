import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class DetailSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const DetailSection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });

  /// Text, or a soft placeholder when the value is missing
  static Widget textOrPlaceholder(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const Text(
        'Not added yet. The club coordinator will update this.',
        style: TextStyle(
          color: AppColors.textMuted,
          fontStyle: FontStyle.italic,
          fontSize: 13.5,
          height: 1.5,
        ),
      );
    }
    return Text(value, style: const TextStyle(fontSize: 14, height: 1.55));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withAlpha(18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}