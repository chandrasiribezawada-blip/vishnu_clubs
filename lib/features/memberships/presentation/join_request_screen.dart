import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../models/club.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../../../shared/widgets/state_views.dart';
import '../../clubs/presentation/widgets/club_card.dart';
import '../../clubs/providers/clubs_providers.dart';
import '../providers/membership_providers.dart';

class JoinRequestScreen extends ConsumerStatefulWidget {
  final int clubId;

  const JoinRequestScreen({super.key, required this.clubId});

  @override
  ConsumerState<JoinRequestScreen> createState() => _JoinRequestScreenState();
}

class _JoinRequestScreenState extends ConsumerState<JoinRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonCtrl = TextEditingController();
  final _skillsCtrl = TextEditingController();
  final _experienceCtrl = TextEditingController();
  bool _loading = false;
  String? _submitError;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _skillsCtrl.dispose();
    _experienceCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final club = ref.read(clubByIdProvider(widget.clubId)).value;
    if (club == null) return;
    if (!_formKey.currentState!.validate()) return;

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    setState(() => _loading = true);
    try {
      await ref
          .read(membershipRepositoryProvider)
          .submitJoinRequest(
            club: club,
            reason: _reasonCtrl.text.trim(),
            skills: _skillsCtrl.text.trim(),
            experience: _experienceCtrl.text.trim().isEmpty
                ? null
                : _experienceCtrl.text.trim(),
          );
      ref.invalidate(joinStatusProvider(widget.clubId));
      ref.invalidate(studentJoinRequestsProvider);
      ref.invalidate(studentMembershipsProvider);
      if (!mounted) return;
      router.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Request sent to ${club.name}. You will be notified once it is reviewed.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _submitError = error is ApiException
            ? error.message
            : 'Could not reach the server. Check your connection and try again.';
      });
    }
  }

  InputDecoration _decoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: true,
      labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clubState = ref.watch(clubByIdProvider(widget.clubId));

    return Scaffold(
      appBar: AppBar(title: const Text('Join request')),
      body: clubState.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (error, _) => ErrorState(
          message: 'Could not load this club.',
          onRetry: () => ref.invalidate(clubsProvider),
        ),
        data: (club) => club == null
            ? const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Club not found',
                message: 'This club may have been removed.',
              )
            : _buildForm(club),
      ),
    );
  }

  Widget _buildForm(Club club) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Club summary
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary.withAlpha(18)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: ClubCard
                            .gradients[club.id % ClubCard.gradients.length],
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      club.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Info note
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(16),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Sending a request does not make you a member. The club coordinator will review it and you will get a notification.',
                      style: TextStyle(fontSize: 12.5, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            if (_submitError case final message?) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withAlpha(14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error.withAlpha(70)),
                ),
                child: Text(
                  message,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
              const SizedBox(height: 14),
            ],

            TextFormField(
              controller: _reasonCtrl,
              maxLines: 4,
              maxLength: 400,
              textInputAction: TextInputAction.next,
              decoration: _decoration(
                'Why do you want to join?',
                'Tell us your reason...',
              ),
              validator: (v) {
                final base = Validators.required(v, 'Reason');
                if (base != null) return base;
                if (v!.trim().length < 20) {
                  return 'Please write at least 20 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _skillsCtrl,
              maxLines: 2,
              maxLength: 200,
              textInputAction: TextInputAction.next,
              decoration: _decoration(
                'Your skills',
                'e.g. Python, public speaking, design',
              ),
              validator: (v) => Validators.required(v, 'Skills'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _experienceCtrl,
              maxLines: 3,
              maxLength: 300,
              decoration: _decoration(
                'Previous experience (optional)',
                'Clubs, projects, events you have been part of',
              ),
            ),
            const SizedBox(height: 20),
            GradientButton(
              label: 'Submit request',
              isLoading: _loading,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
