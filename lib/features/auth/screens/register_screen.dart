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

    return Scaffold(
      appBar: AppBar(title: Text('auth.createAccount'.tr())),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _loading,
          child: Column(
            children: [
              Expanded(
                child: Stepper(
                  type: StepperType.horizontal,
                  currentStep: _currentStep,
                  onStepContinue: _onContinue,
                  onStepCancel:
                      _currentStep > 0 ? () => setState(() => _currentStep--) : null,
                  // Allow jumping back to a completed step, not skipping ahead.
                  onStepTapped: (i) {
                    if (i < _currentStep) setState(() => _currentStep = i);
                  },
                  controlsBuilder: (context, details) => Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _loading ? null : details.onStepContinue,
                            child: _loading && isLast
                                ? SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Theme.of(context).colorScheme.onPrimary,
                                    ),
                                  )
                                : Text(isLast
                                    ? 'auth.createAccount'.tr()
                                    : 'common.continue'.tr()),
                          ),
                        ),
                        if (_currentStep > 0) ...[
                          const SizedBox(width: 12),
                          OutlinedButton(
                            onPressed: _loading ? null : details.onStepCancel,
                            child: Text('common.back'.tr()),
                          ),
                        ],
                      ],
                    ),
                  ),
                  steps: [
                    Step(
                      title: Text('auth.stepName'.tr()),
                      isActive: _currentStep >= 0,
                      state: _currentStep > 0 ? StepState.complete : StepState.indexed,
                      content: Form(
                        key: _stepKeys[0],
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _field(_firstName, 'auth.firstName'.tr(), validator: _required),
                            _field(_middleName,
                                '${'auth.middleName'.tr()} (${'auth.optional'.tr()})'),
                            _field(_lastName, 'auth.lastName'.tr(), validator: _required),
                          ],
                        ),
                      ),
                    ),
                    Step(
                      title: Text('auth.stepAccount'.tr()),
                      isActive: _currentStep >= 1,
                      state: _currentStep > 1 ? StepState.complete : StepState.indexed,
                      content: Form(
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
                      ),
                    ),
                    Step(
                      title: Text('auth.stepSecurity'.tr()),
                      isActive: _currentStep >= 2,
                      state: StepState.indexed,
                      content: Form(
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
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('auth.haveAccount'.tr()),
                    TextButton(
                      onPressed: () => context.go(Routes.login),
                      child: Text('auth.signIn'.tr()),
                    ),
                  ],
                ),
              ),
            ],
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
