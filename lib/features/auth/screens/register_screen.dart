import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/country_picker.dart';
import '../providers/auth_controller.dart';

/// One short sign-up screen: Google first, or phone + username + email +
/// password. Names and income are asked later, in context. There is no SMS
/// code: phones cannot be verified.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

/// A username suggestion from an email's local part: lower case, letters,
/// digits, dots and underscores only.
String suggestUsername(String email) {
  final local = email.split('@').first.split('+').first.toLowerCase();
  final clean = local.replaceAll(RegExp(r'[^a-z0-9._]'), '');
  return clean.length > 30 ? clean.substring(0, 30) : clean;
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  Country _country = malawi;
  bool _obscure = true;
  bool _loading = false;
  bool _accepted = false;

  /// Until the user types their own username, it follows the email.
  bool _usernameEdited = false;

  @override
  void initState() {
    super.initState();
    _email.addListener(_suggestUsername);
  }

  @override
  void dispose() {
    for (final c in [_phone, _username, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  void _suggestUsername() {
    if (_usernameEdited) return;
    final suggestion = suggestUsername(_email.text);
    if (suggestion != _username.text) _username.text = suggestion;
  }

  void _openLegal(String slug) => context.push('${Routes.legal}?slug=$slug');

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_accepted) {
      _showError('auth.mustAcceptTerms'.tr());
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(authControllerProvider.notifier).register(
            phoneNumber: internationalNumber(_country, _phone.text),
            email: _email.text.trim(),
            password: _password.text,
            username: _username.text.trim(),
            acceptedTerms: _accepted,
          );
      // The router moves on (SMS step on Android, else Home).
    } on ApiException catch (e) {
      _showError(e.displayMessage);
    } catch (_) {
      _showError('common.somethingWrong'.tr());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _google() async {
    setState(() => _loading = true);
    try {
      await ref.read(authControllerProvider.notifier).signInWithGoogle();
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
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _loading,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('auth.signUpTitle'.tr(), style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: AppSpacing.xs),
                  Text('auth.registerSubtitle'.tr(), style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    key: const ValueKey('signup-google'),
                    onPressed: _loading ? null : _google,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    icon: const Icon(Icons.g_mobiledata, size: 28),
                    label: Text('auth.continueWithGoogle'.tr()),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                        child: Text('auth.orWithPhone'.tr(), style: TextStyle(color: scheme.onSurfaceVariant)),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Phone: country button + local number.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CountryCodeButton(
                        country: _country,
                        onChanged: (c) => setState(() => _country = c),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('signup-phone'),
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.telephoneNumberNational],
                          decoration: InputDecoration(labelText: 'auth.phoneNumber'.tr()),
                          validator: _phoneValidator,
                        ),
                      ),
                    ],
                  ),
                  if (_country != malawi) ...[
                    const SizedBox(height: AppSpacing.md),
                    _Notice(text: 'auth.foreignNotice'.tr()),
                  ],
                  const SizedBox(height: AppSpacing.lg),

                  // Username and email side by side.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('signup-username'),
                          controller: _username,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          decoration: InputDecoration(labelText: 'auth.username'.tr()),
                          onChanged: (_) => _usernameEdited = true,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('signup-email'),
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.email],
                          decoration: InputDecoration(labelText: 'auth.email'.tr()),
                          validator: _emailValidator,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    key: const ValueKey('signup-password'),
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'auth.createPassword'.tr(),
                      helperText: 'auth.passwordHint'.tr(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: _passwordValidator,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'auth.signInLaterHelper'.tr(),
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Terms: one checkbox, with links to read them.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        key: const ValueKey('signup-terms'),
                        value: _accepted,
                        onChanged: (v) => setState(() => _accepted = v ?? false),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text('${'auth.agreePrefix'.tr()} '),
                              _LegalLink('auth.terms'.tr(), () => _openLegal('terms')),
                              Text(' ${'auth.and'.tr()} '),
                              _LegalLink('auth.privacy'.tr(), () => _openLegal('privacy')),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    key: const ValueKey('signup-submit'),
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    child: _loading
                        ? SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: scheme.onPrimary),
                          )
                        : Text('auth.createAccount'.tr()),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
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

  String? _phoneValidator(String? v) {
    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return 'auth.required'.tr();
    if (digits.length < 6 || digits.length > 14) return 'auth.invalidPhone'.tr();
    return null;
  }

  String? _emailValidator(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'auth.required'.tr();
    if (!value.contains('@') || !value.contains('.')) return 'auth.invalidEmail'.tr();
    return null;
  }

  String? _passwordValidator(String? v) {
    if (v == null || v.isEmpty) return 'auth.required'.tr();
    if (v.length < 8) return 'auth.passwordHint'.tr();
    return null;
  }
}

/// A quiet information line (icon + text) on a tinted surface.
class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('signup-foreign-notice'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4))),
        ],
      ),
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}
