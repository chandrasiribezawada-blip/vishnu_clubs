import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../models/club.dart';
import '../../../clubs/presentation/widgets/club_card.dart';

class ClubMiniCard extends StatelessWidget {
  final Club club;
  final VoidCallback? onTap;

  const ClubMiniCard({super.key, required this.club, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = ClubCard.gradients[club.id % ClubCard.gradients.length];

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: 152,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withAlpha(18)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withAlpha(14),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                club.initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              club.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            const Spacer(),
            if (club.category case final category?)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.first.withAlpha(24),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  category,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.first,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}