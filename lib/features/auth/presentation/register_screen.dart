import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../providers/auth_providers.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _regNoCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  String? _department;
  String? _year;
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _regNoCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .register(
            fullName: _nameCtrl.text,
            email: _emailCtrl.text,
            registrationNumber: _regNoCtrl.text,
            department: _department!,
            year: _year!,
            phoneNumber: _phoneCtrl.text,
            password: _passwordCtrl.text,
          );
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      final message = error is ApiException
          ? error.message
          : 'Could not connect to VishnuConnect. Check your connection and try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Widget _dropdown({
    required String label,
    required IconData icon,
    required List<String> items,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        prefixIcon: Icon(icon, color: AppColors.textMuted),
      ),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: onChanged,
      validator: (v) => v == null ? 'Please select $label' : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Create your account',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Create a student account to join your college community',
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Coordinator access is assigned by a club admin. Admin '
                  'accounts are created by the project administrator. '
                  'Account roles cannot be self-selected.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
              const SizedBox(height: 20),
              AppTextField(
                label: 'Full name',
                icon: Icons.person_outline_rounded,
                controller: _nameCtrl,
                validator: (v) => Validators.required(v, 'Name'),
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'College email',
                icon: Icons.mail_outline_rounded,
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                validator: Validators.email,
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'Registration number',
                icon: Icons.badge_outlined,
                controller: _regNoCtrl,
                validator: (v) => Validators.required(v, 'Registration number'),
              ),
              const SizedBox(height: 14),
              _dropdown(
                label: 'Department',
                icon: Icons.apartment_rounded,
                items: AppConstants.departments,
                value: _department,
                onChanged: (v) => setState(() => _department = v),
              ),
              const SizedBox(height: 14),
              _dropdown(
                label: 'Year',
                icon: Icons.school_outlined,
                items: AppConstants.years,
                value: _year,
                onChanged: (v) => setState(() => _year = v),
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'Phone number',
                icon: Icons.phone_outlined,
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                validator: Validators.phone,
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'Password',
                icon: Icons.lock_outline_rounded,
                controller: _passwordCtrl,
                isPassword: true,
                validator: Validators.newPassword,
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'Confirm password',
                icon: Icons.lock_reset_rounded,
                controller: _confirmCtrl,
                isPassword: true,
                textInputAction: TextInputAction.done,
                validator: Validators.confirmPassword(() => _passwordCtrl.text),
              ),
              const SizedBox(height: 28),
              GradientButton(
                label: 'Create account',
                isLoading: _loading,
                onPressed: _submit,
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Already have an account? Log in'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
