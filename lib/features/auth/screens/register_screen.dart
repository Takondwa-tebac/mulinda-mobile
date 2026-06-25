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
  // One form per step so each step validates only its own fields.
  final _stepKeys = [GlobalKey<FormState>(), GlobalKey<FormState>(), GlobalKey<FormState>()];
  int _currentStep = 0;
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
  bool _accepted = false;

  @override
  void dispose() {
    for (final c in [_firstName, _middleName, _lastName, _username, _phone, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  void _openLegal(String slug) => context.push('${Routes.legal}?slug=$slug');

  static const _lastStep = 2;

  /// Validate the current step, then advance — or submit on the final step.
  void _onContinue() {
    if (!(_stepKeys[_currentStep].currentState?.validate() ?? false)) return;
    if (_currentStep < _lastStep) {
      setState(() => _currentStep++);
    } else {
      _submit();
    }
  }

  Future<void> _submit() async {
    if (!_accepted) {
      _showError('auth.mustAcceptTerms'.tr());
      return;
    }
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
    final isLast = _currentStep == _lastStep;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('auth.createAccount'.tr())),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _loading,
          child: Column(
            children: [
              _StepHeader(
                current: _currentStep,
                titles: [
                  'auth.stepName'.tr(),
                  'auth.stepAccount'.tr(),
                  'auth.stepSecurity'.tr(),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: _stepForm(_currentStep),
                ),
              ),
              // Fixed bottom action bar — buttons always get full width here,
              // unlike the cramped controls area of a horizontal Stepper.
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Row(
                  children: [
                    if (_currentStep > 0) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              _loading ? null : () => setState(() => _currentStep--),
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50)),
                          child: Text('common.back'.tr()),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _loading ? null : _onContinue,
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50)),
                        child: _loading && isLast
                            ? SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: scheme.onPrimary,
                                ),
                              )
                            : Text(isLast
                                ? 'auth.createAccount'.tr()
                                : 'common.continue'.tr()),
                      ),
                    ),
                  ],
                ),
              ),
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
    );
  }

  /// The form for the given step. Controllers persist across steps, so values
  /// are retained when the user navigates back and forth.
  Widget _stepForm(int step) {
    switch (step) {
      case 0:
        return Form(
          key: _stepKeys[0],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(_firstName, 'auth.firstName'.tr(), validator: _required),
              _field(_middleName, '${'auth.middleName'.tr()} (${'auth.optional'.tr()})'),
              _field(_lastName, 'auth.lastName'.tr(), validator: _required),
            ],
          ),
        );
      case 1:
        return Form(
          key: _stepKeys[1],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(_username, 'auth.username'.tr(), validator: _required),
              _field(_phone, 'auth.phoneNumber'.tr(),
                  keyboardType: TextInputType.phone, validator: _required),
              _field(_email, 'auth.email'.tr(),
                  keyboardType: TextInputType.emailAddress, validator: _email_),
            ],
          ),
        );
      default:
        return Form(
          key: _stepKeys[2],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(_password, 'auth.password'.tr(),
                  obscure: true,
                  validator: _passwordValidator,
                  helper: 'auth.passwordHint'.tr()),
              _field(_confirm, 'auth.confirmPassword'.tr(),
                  obscure: true, validator: _confirmValidator),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _accepted,
                    onChanged: (v) => setState(() => _accepted = v ?? false),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('auth.agreePrefix'.tr()),
                          _LegalLink('auth.terms'.tr(), () => _openLegal('terms')),
                          Text(' ${'auth.and'.tr()} '),
                          _LegalLink('auth.privacy'.tr(), () => _openLegal('privacy')),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
    }
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

/// Numbered progress header for the signup wizard (e.g. ①─②─③ with the
/// current step highlighted and completed steps ticked).
class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.current, required this.titles});

  final int current;
  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          for (var i = 0; i < titles.length; i++) ...[
            _Dot(
              index: i,
              current: current,
              label: titles[i],
            ),
            if (i < titles.length - 1)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 18),
                  color: i < current ? scheme.primary : scheme.outlineVariant,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.index, required this.current, required this.label});

  final int index;
  final int current;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = index < current;
    final active = index == current;
    final bg = done || active ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = done || active ? scheme.onPrimary : scheme.onSurfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: bg,
          child: done
              ? Icon(Icons.check, size: 16, color: fg)
              : Text('${index + 1}',
                  style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 72,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              color: active ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}
