import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/auth_repository.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).forgotPassword(_email.text.trim());
      if (!mounted) return;
      _snack('auth.resetSent'.tr());
      Navigator.of(context).maybePop();
    } on ApiException catch (e) {
      // e.g. 404 "No account found with that email. Please register."
      if (!mounted) return;
      _snack(e.displayMessage);
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      _snack('auth.googleUnavailable'.tr());
      setState(() => _loading = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text('auth.resetTitle'.tr())),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('auth.resetSubtitle'.tr(),
                    style: text.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: 'auth.email'.tr()),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'auth.required'.tr();
                    if (!v.contains('@') || !v.contains('.')) return 'auth.invalidEmail'.tr();
                    return null;
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        )
                      : Text('auth.sendResetLink'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
