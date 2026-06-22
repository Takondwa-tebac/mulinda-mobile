import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../providers/auth_controller.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _lastName = TextEditingController();
  final _username = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    for (final c in [_firstName, _middleName, _lastName, _username, _phone, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(authControllerProvider.notifier).register(
            firstName: _firstName.text.trim(),
            middleName: _middleName.text.trim(),
            lastName: _lastName.text.trim(),
            username: _username.text.trim(),
            phoneNumber: _phone.text.trim(),
            email: _email.text.trim(),
            password: _password.text,
            passwordConfirmation: _confirm.text,
          );
      // Router guard redirects to home on success.
    } on ApiException catch (e) {
      _showError(e.displayMessage);
    } catch (_) {
      _showError('auth.googleUnavailable'.tr());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _loading,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('auth.createAccount'.tr(),
                      style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('auth.registerSubtitle'.tr(),
                      style: text.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 24),
                  _field(_firstName, 'auth.firstName'.tr(), validator: _required),
                  _field(_middleName, 'auth.middleName'.tr()),
                  _field(_lastName, 'auth.lastName'.tr(), validator: _required),
                  _field(_username, 'auth.username'.tr(), validator: _required),
                  _field(_phone, 'auth.phoneNumber'.tr(),
                      keyboardType: TextInputType.phone, validator: _required),
                  _field(_email, 'auth.email'.tr(),
                      keyboardType: TextInputType.emailAddress, validator: _email_),
                  _field(_password, 'auth.password'.tr(),
                      obscure: true, validator: _passwordValidator, helper: 'auth.passwordHint'.tr()),
                  _field(_confirm, 'auth.confirmPassword'.tr(),
                      obscure: true, validator: _confirmValidator),
                  const SizedBox(height: 12),
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
                        : Text('auth.createAccount'.tr()),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('auth.haveAccount'.tr()),
                      TextButton(
                        onPressed: () => context.go(Routes.login),
                        child: Text('auth.signIn'.tr()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool obscure = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    String? helper,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        obscureText: obscure && _obscure,
        keyboardType: keyboardType,
        textInputAction: TextInputAction.next,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          suffixIcon: obscure
              ? IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                )
              : null,
        ),
      ),
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'auth.required'.tr() : null;

  String? _email_(String? v) {
    if (v == null || v.trim().isEmpty) return 'auth.required'.tr();
    if (!v.contains('@') || !v.contains('.')) return 'auth.invalidEmail'.tr();
    return null;
  }

  String? _passwordValidator(String? v) {
    if (v == null || v.isEmpty) return 'auth.required'.tr();
    if (v.length < 8) return 'auth.passwordHint'.tr();
    return null;
  }

  String? _confirmValidator(String? v) {
    if (v != _password.text) return 'auth.passwordsDontMatch'.tr();
    return null;
  }
}
