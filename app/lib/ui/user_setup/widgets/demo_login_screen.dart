import 'package:flutter/material.dart';

import '../../core/themes/app_colors.dart';
import '../../core/themes/app_shadows.dart';
import '../../core/themes/app_text_styles.dart';
import '../../../data/services/supabase_service.dart';

/// DearCocoa login: the five demo accounts are prefilled and selectable with
/// one tap — no wall between the user and the app. Custom email/password
/// sign-in stays available below the demo list.
class DemoLoginScreen extends StatefulWidget {
  const DemoLoginScreen({super.key, required this.onSignedIn});

  final VoidCallback onSignedIn;

  @override
  State<DemoLoginScreen> createState() => _DemoLoginScreenState();
}

class _DemoLoginScreenState extends State<DemoLoginScreen> {
  bool _busy = false;
  int? _busyIndex;
  String? _error;
  bool _showCustom = false;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn(Future<void> Function() action) async {
    setState(() => _error = null);
    try {
      await action();
      if (mounted) widget.onSignedIn();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Sign-in failed: ${_friendlyError(e)}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyIndex = null;
        });
      }
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('Invalid login')) return 'wrong email or password';
    if (s.contains('Email not confirmed')) return 'email not confirmed';
    if (s.contains('Failed host lookup')) return 'no network connection';
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('DearCocoa', style: AppTextStyles.brandTitle()),
                  const SizedBox(height: 8),
                  Text(
                    'Your gentle social wellness space.\nPick an account to step right in:',
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ..._buildDemoAccounts(),
                  const SizedBox(height: 8),
                  _buildCustomSection(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDemoAccounts() {
    final accounts = SupabaseService.demoAccounts;
    return [
      for (var i = 0; i < accounts.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _DemoAccountCard(
            account: accounts[i],
            busy: _busy && _busyIndex == i,
            enabled: !_busy,
            onTap: () {
              setState(() {
                _busy = true;
                _busyIndex = i;
              });
              _signIn(() async {
                await SupabaseService.instance.signInDemo(accounts[i]);
              });
            },
          ),
        ),
    ];
  }

  Widget _buildCustomSection() {
    if (!_showCustom) {
      return TextButton(
        onPressed: () => setState(() => _showCustom = true),
        child: const Text(
          'Sign in with another account',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [AppShadows.card],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || !v.contains('@')) ? 'Enter an email' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.length < 6)
                  ? 'Minimum 6 characters'
                  : null,
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: _busy
                  ? null
                  : () {
                      if (!_formKey.currentState!.validate()) return;
                      setState(() => _busy = true);
                      _signIn(() async {
                        await SupabaseService.instance.signIn(
                          _emailController.text.trim(),
                          _passwordController.text,
                        );
                      });
                    },
              child: Text(_busy ? 'Signing in…' : 'Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DemoAccountCard extends StatelessWidget {
  const _DemoAccountCard({
    required this.account,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  final DemoAccount account;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [AppShadows.card],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: AppColors.avatarGradient,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  account.name[0],
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      account.email,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.chevron_right,
                      color: AppColors.textTertiary,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
