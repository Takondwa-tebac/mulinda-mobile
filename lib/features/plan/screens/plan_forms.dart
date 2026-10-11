import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/currencies.dart';
import '../../../core/money/money.dart';
import '../../../core/network/api_exception.dart';
import '../../activity/widgets/category_picker.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../data/investment_types.dart';
import '../data/plan_models.dart';
import '../data/plan_repository.dart';
import '../widgets/mse_logo.dart';
import '../widgets/plan_form_kit.dart';

const _goalTypes = ['emergency', 'house', 'car', 'business', 'education', 'vacation', 'custom'];
const _interestTypes = ['reducing_balance', 'flat'];
const _loanStatuses = ['active', 'paid_off', 'defaulted', 'closed'];
const _investStatuses = ['active', 'matured', 'sold', 'closed'];
const _interestPeriods = ['annual', 'monthly'];
const _projectStatuses = ['planning', 'active', 'on_hold', 'completed'];

List<(String, String)> _entries(List<String> values, String prefix) =>
    values.map((v) => (v, '$prefix.$v'.tr())).toList();

/// Wraps a save action: loading, error snackbar, invalidate, pop.
mixin _FormSubmit<W extends StatefulWidget> on State<W> {
  bool loading = false;

  Future<void> submit(
    WidgetRef ref,
    Future<void> Function() action,
    ProviderOrFamily listProvider,
  ) async {
    setState(() => loading = true);
    try {
      await action();
      ref.invalidate(listProvider);
      ref.invalidate(dashboardProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('form.saved'.tr())));
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.displayMessage)));
        setState(() => loading = false);
      }
    }
  }
}

double _major(Money m) => m.amount;

// ---------------------------------------------------------------- Goal -------

class GoalForm extends ConsumerStatefulWidget {
  const GoalForm({super.key, this.item});
  final GoalItem? item;

  @override
  ConsumerState<GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends ConsumerState<GoalForm> with _FormSubmit {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _target = TextEditingController(
      text: widget.item == null ? '' : _major(widget.item!.target).toStringAsFixed(0));
  late final _monthly = TextEditingController(
      text: widget.item?.monthlyContribution == null ? '' : _major(widget.item!.monthlyContribution!).toStringAsFixed(0));
  late String _type = widget.item?.type ?? 'custom';
  late DateTime? _targetDate = apiToDate(widget.item?.targetDate);

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _monthly.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'type': _type,
      'target': double.parse(_target.text.trim()),
    };
    if (_targetDate != null) data['target_date'] = dateToApi(_targetDate);
    if (_monthly.text.trim().isNotEmpty) data['monthly_contribution'] = double.parse(_monthly.text.trim());

    final repo = ref.read(planRepositoryProvider);
    submit(ref, () => widget.item == null ? repo.createGoal(data) : repo.updateGoal(widget.item!.id, data), goalsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final edit = widget.item != null;
    return _Scaffold(
      title: edit ? 'form.editGoal'.tr() : 'form.newGoal'.tr(),
      formKey: _formKey,
      loading: loading,
      onSave: _save,
      saveLabel: edit ? 'form.save'.tr() : 'form.create'.tr(),
      children: [
        pkText(controller: _name, label: 'form.name'.tr(), validator: _req),
        pkDropdown<String>(value: _type, label: 'form.type'.tr(), entries: _entries(_goalTypes, 'form.goalType'), onChanged: (v) => setState(() => _type = v)),
        pkMoney(controller: _target, label: 'form.target'.tr()),
        pkDate(context: context, label: 'form.targetDate'.tr(), value: _targetDate, firstDate: DateTime.now().add(const Duration(days: 1)), onPick: (d) => setState(() => _targetDate = d)),
        pkMoney(controller: _monthly, label: 'form.monthly'.tr(), required: false),
      ],
    );
  }
}

// -------------------------------------------------------------- Budget -------

class BudgetForm extends ConsumerStatefulWidget {
  const BudgetForm({super.key, this.item});
  final BudgetItem? item;

  @override
  ConsumerState<BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends ConsumerState<BudgetForm> with _FormSubmit {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _limit = TextEditingController(
      text: widget.item == null ? '' : _major(widget.item!.limit).toStringAsFixed(0));
  late final _alert = TextEditingController(
      text: ((widget.item?.alertThreshold ?? 0.8) * 100).toStringAsFixed(0));
  late String _period = widget.item?.period ?? 'monthly';
  late String? _categoryId = widget.item?.categoryId;

  @override
  void dispose() {
    _name.dispose();
    _limit.dispose();
    _alert.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final data = <String, dynamic>{
      'period': _period,
      'limit': double.parse(_limit.text.trim()),
      'is_active': true,
    };
    if (_name.text.trim().isNotEmpty) data['name'] = _name.text.trim();
    if (_categoryId != null) data['category_id'] = _categoryId;
    final alert = double.tryParse(_alert.text.trim());
    if (alert != null) data['alert_threshold'] = (alert / 100).clamp(0, 1);

    final repo = ref.read(planRepositoryProvider);
    submit(ref, () => widget.item == null ? repo.createBudget(data) : repo.updateBudget(widget.item!.id, data), budgetsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final edit = widget.item != null;
    return _Scaffold(
      title: edit ? 'form.editBudget'.tr() : 'form.newBudget'.tr(),
      formKey: _formKey,
      loading: loading,
      onSave: _save,
      saveLabel: edit ? 'form.save'.tr() : 'form.create'.tr(),
      children: [
        pkText(controller: _name, label: 'form.name'.tr()),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: CategoryPickerField(
            value: _categoryId,
            kind: 'expense',
            onChanged: (v) => setState(() => _categoryId = v),
          ),
        ),
        pkDropdown<String>(value: _period, label: 'form.period'.tr(), entries: [('weekly', 'form.weekly'.tr()), ('monthly', 'form.monthly_period'.tr())], onChanged: (v) => setState(() => _period = v)),
        pkMoney(controller: _limit, label: 'form.limit'.tr()),
        pkText(controller: _alert, label: 'form.alertThreshold'.tr(), keyboard: TextInputType.number),
      ],
    );
  }
}

// ---------------------------------------------------------------- Loan -------

class LoanForm extends ConsumerStatefulWidget {
  const LoanForm({super.key, this.item});
  final LoanItem? item;

  @override
  ConsumerState<LoanForm> createState() => _LoanFormState();
}

class _LoanFormState extends ConsumerState<LoanForm> with _FormSubmit {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _lender = TextEditingController(text: widget.item?.lender ?? '');
  late final _principal = TextEditingController(
      text: widget.item == null ? '' : _major(widget.item!.principal).toStringAsFixed(0));
  late final _rate = TextEditingController(
      text: widget.item == null ? '' : (widget.item!.annualInterestRate * 100).toStringAsFixed(1));
  late final _term = TextEditingController(text: widget.item?.termMonths.toString() ?? '12');
  late String _interestType = widget.item?.interestType ?? 'reducing_balance';
  late String _status = widget.item?.status ?? 'active';
  late DateTime _disbursedAt = apiToDate(widget.item?.disbursedAt) ?? DateTime.now();
  late DateTime? _firstPayment = apiToDate(widget.item?.firstPaymentDate);

  @override
  void dispose() {
    _name.dispose();
    _lender.dispose();
    _principal.dispose();
    _rate.dispose();
    _term.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'principal': double.parse(_principal.text.trim()),
      'interest_type': _interestType,
      'term_months': int.parse(_term.text.trim()),
      'status': _status,
      'disbursed_at': dateToApi(_disbursedAt),
    };
    if (_lender.text.trim().isNotEmpty) data['lender'] = _lender.text.trim();
    final rate = double.tryParse(_rate.text.trim());
    if (rate != null) data['annual_interest_rate'] = rate / 100;
    if (_firstPayment != null) data['first_payment_date'] = dateToApi(_firstPayment);

    final repo = ref.read(planRepositoryProvider);
    submit(ref, () => widget.item == null ? repo.createLoan(data) : repo.updateLoan(widget.item!.id, data), loansProvider);
  }

  @override
  Widget build(BuildContext context) {
    final edit = widget.item != null;
    return _Scaffold(
      title: edit ? 'form.editLoan'.tr() : 'form.newLoan'.tr(),
      formKey: _formKey,
      loading: loading,
      onSave: _save,
      saveLabel: edit ? 'form.save'.tr() : 'form.create'.tr(),
      children: [
        pkText(controller: _name, label: 'form.name'.tr(), validator: _req),
        pkText(controller: _lender, label: 'form.lender'.tr()),
        pkMoney(controller: _principal, label: 'form.principal'.tr()),
        pkText(controller: _rate, label: 'form.interestRate'.tr(), keyboard: const TextInputType.numberWithOptions(decimal: true)),
        pkDropdown<String>(value: _interestType, label: 'form.interestType'.tr(), entries: _entries(_interestTypes, 'form.interestTypes'), onChanged: (v) => setState(() => _interestType = v)),
        pkText(controller: _term, label: 'form.termMonths'.tr(), keyboard: TextInputType.number, validator: _req),
        pkDropdown<String>(value: _status, label: 'form.status'.tr(), entries: _entries(_loanStatuses, 'form.loanStatus'), onChanged: (v) => setState(() => _status = v)),
        pkDate(context: context, label: 'form.disbursedAt'.tr(), value: _disbursedAt, onPick: (d) => setState(() => _disbursedAt = d)),
        pkDate(context: context, label: 'form.firstPayment'.tr(), value: _firstPayment, onPick: (d) => setState(() => _firstPayment = d)),
      ],
    );
  }
}

// ---------------------------------------------------------- Investment -------

class InvestmentForm extends ConsumerStatefulWidget {
  const InvestmentForm({super.key, this.item});
  final InvestmentItem? item;

  @override
  ConsumerState<InvestmentForm> createState() => _InvestmentFormState();
}

class _InvestmentFormState extends ConsumerState<InvestmentForm> with _FormSubmit {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _amount = TextEditingController(
      text: widget.item == null ? '' : _major(widget.item!.amountInvested).toStringAsFixed(0));
  late final _value = TextEditingController(
      text: widget.item == null ? '' : _major(widget.item!.value).toStringAsFixed(0));
  late final _return = TextEditingController(
      text: widget.item?.expectedReturn == null ? '' : (widget.item!.expectedReturn! * 100).toStringAsFixed(1));
  late final _notes = TextEditingController(text: widget.item?.notes ?? '');
  late String _type = widget.item?.type ?? 'fixed_deposit';
  late String _status = widget.item?.status ?? 'active';
  late String _interestPeriod = widget.item?.interestPeriod ?? 'annual';
  late DateTime _startedAt = apiToDate(widget.item?.startedAt) ?? DateTime.now();
  late DateTime? _maturity = apiToDate(widget.item?.maturityDate);
  late bool _remind = widget.item?.remindersEnabled ?? true;

  // What is specific to the chosen type (units and price of shares, a SACCO's
  // member number...), keyed by the field's key.
  final Map<String, TextEditingController> _detailText = {};
  final Map<String, DateTime?> _detailDates = {};
  final Map<String, String?> _detailSelects = {};
  final Map<String, FocusNode> _focusNodes = {};

  String get _currency => widget.item?.amountInvested.currency ?? 'MWK';

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _value.dispose();
    _return.dispose();
    _notes.dispose();
    for (final c in _detailText.values) {
      c.dispose();
    }
    for (final n in _focusNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  Object? _saved(String key) => widget.item?.details[key];

  TextEditingController _controllerFor(InvestmentField f) => _detailText.putIfAbsent(f.key, () {
        final v = _saved(f.key);
        final text = v == null ? '' : (v is num && v == v.roundToDouble() ? v.toInt().toString() : v.toString());
        final c = TextEditingController(text: text);
        c.addListener(() => setState(() {}));
        return c;
      });

  Map<String, double?> _numbers(InvestmentTypeDef def) => {
        for (final f in def.fields)
          if (f.isNumeric) f.key: double.tryParse(_controllerFor(f).text.trim()),
      };

  String _money(double v) {
    final whole = v == v.roundToDouble();
    final parts = v.toStringAsFixed(whole ? 0 : 2).split('.');
    final grouped = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    final symbol = currencyInfo(_currency).symbol;
    return parts.length > 1 ? '$symbol $grouped.${parts[1]}' : '$symbol $grouped';
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _save(InvestmentTypeDef def) {
    if (!_formKey.currentState!.validate()) return;

    final details = <String, dynamic>{};
    for (final f in def.fields) {
      switch (f.kind) {
        case 'date':
          final d = _detailDates[f.key] ?? apiToDate(_saved(f.key)?.toString());
          if (d == null && f.required) return _toast('auth.required'.tr());
          if (d != null) details[f.key] = dateToApi(d);
        case 'select':
          final v = _detailSelects[f.key] ?? _saved(f.key)?.toString();
          if (v == null && f.required) return _toast('auth.required'.tr());
          if (v != null) details[f.key] = v;
        default:
          final raw = _controllerFor(f).text.trim();
          if (raw.isEmpty) continue;
          details[f.key] = f.isNumeric ? double.parse(raw) : raw;
      }
    }

    if (def.requiresMaturity && _maturity == null) return _toast('auth.required'.tr());

    final derived = def.derive(_numbers(def));
    double? invested;
    if (def.derivesAmountInvested) {
      invested = derived.invested;
      if (invested == null || invested <= 0) return _toast('auth.required'.tr());
    } else {
      invested = double.parse(_amount.text.trim());
    }

    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'type': _type,
      'status': _status,
      'amount_invested': invested,
      'started_at': dateToApi(_startedAt),
    };

    // The server works these out again and its answer wins; they are sent too so a
    // change made offline already shows the right figures.
    if (def.derivesValue) {
      if (derived.value != null) data['current_value'] = derived.value;
    } else if (_value.text.trim().isNotEmpty) {
      data['current_value'] = double.parse(_value.text.trim());
    }

    if (def.interest) {
      data['interest_period'] = _interestPeriod;
      final ret = double.tryParse(_return.text.trim());
      if (ret != null) data['expected_annual_return'] = ret / 100;
    }
    if (def.requiresMaturity) data['maturity_date'] = dateToApi(_maturity);
    if (def.fields.isNotEmpty) data['details'] = details;
    if (def.reminders.isNotEmpty) data['reminders_enabled'] = _remind;
    if (_notes.text.trim().isNotEmpty) data['notes'] = _notes.text.trim();

    final repo = ref.read(planRepositoryProvider);
    submit(ref, () => widget.item == null ? repo.createInvestment(data) : repo.updateInvestment(widget.item!.id, data), investmentsListProvider);
  }

  /// A text field that suggests names as you type (companies listed on the Malawi
  /// Stock Exchange for shares). Picking one also fills the ticker and where it is
  /// traded; typing something else is fine.
  Widget _suggestField(InvestmentField f, String label) {
    final controller = _controllerFor(f);
    final focus = _focusNodes.putIfAbsent(f.key, FocusNode.new);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: RawAutocomplete<InvestmentOption>(
        textEditingController: controller,
        focusNode: focus,
        displayStringForOption: (o) => o.label('en'),
        optionsBuilder: (value) {
          final q = value.text.trim().toLowerCase();
          if (q.isEmpty) return f.suggestions;
          return f.suggestions.where((o) => o.label('en').toLowerCase().contains(q) || o.value.toLowerCase().contains(q));
        },
        onSelected: (o) => setState(() {
          final ticker = _detailText['ticker'];
          if (ticker != null && ticker.text.trim().isEmpty) ticker.text = o.value;
          _detailSelects['exchange'] ??= 'mse';
        }),
        fieldViewBuilder: (context, textController, focusNode, onSubmit) => TextFormField(
          controller: textController,
          focusNode: focusNode,
          decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.search)),
          validator: (v) => f.required && (v ?? '').trim().isEmpty ? 'auth.required'.tr() : null,
        ),
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 420),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final o in options)
                    ListTile(
                      dense: true,
                      leading: MseLogo(ticker: o.value, name: o.label('en'), size: 32),
                      title: Text(o.label('en')),
                      trailing: Text(o.value, style: Theme.of(context).textTheme.labelSmall),
                      onTap: () => onSelected(o),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldWidget(InvestmentField f, String lang) {
    final label = f.label(lang);
    switch (f.kind) {
      case 'date':
        return pkDate(
          context: context,
          label: label,
          value: _detailDates[f.key] ?? apiToDate(_saved(f.key)?.toString()),
          onPick: (d) => setState(() => _detailDates[f.key] = d),
          required: false,
        );
      case 'select':
        final current = _detailSelects[f.key] ?? _saved(f.key)?.toString();
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: DropdownButtonFormField<String>(
            initialValue: f.options.any((o) => o.value == current) ? current : null,
            decoration: InputDecoration(labelText: label),
            items: [for (final o in f.options) DropdownMenuItem(value: o.value, child: Text(o.label(lang)))],
            validator: f.required ? (v) => v == null ? 'auth.required'.tr() : null : null,
            onChanged: (v) => setState(() => _detailSelects[f.key] = v),
          ),
        );
      default:
        if (f.suggestions.isNotEmpty) return _suggestField(f, label);
        return pkText(
          controller: _controllerFor(f),
          label: label,
          keyboard: f.isNumeric ? const TextInputType.numberWithOptions(decimal: true) : null,
          validator: (v) {
            final text = (v ?? '').trim();
            if (text.isEmpty) return f.required ? 'auth.required'.tr() : null;
            if (f.isNumeric && double.tryParse(text) == null) return 'auth.required'.tr();
            return null;
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final edit = widget.item != null;
    final lang = context.locale.languageCode;
    final defs = ref.watch(investmentTypesProvider).valueOrNull ?? fallbackInvestmentTypes;
    final def = defs.firstWhere(
      (d) => d.type == _type,
      orElse: () => InvestmentTypeDef(type: _type, labels: {'en': _type}, interest: true),
    );
    final scheme = Theme.of(context).colorScheme;
    final derived = def.derive(_numbers(def));
    final description = def.description(lang);

    return _Scaffold(
      title: edit ? 'form.editInvestment'.tr() : 'form.newInvestment'.tr(),
      formKey: _formKey,
      loading: loading,
      onSave: () => _save(def),
      saveLabel: edit ? 'form.save'.tr() : 'form.create'.tr(),
      children: [
        pkDropdown<String>(
          value: _type,
          label: 'form.type'.tr(),
          entries: [
            for (final d in defs) (d.type, 'form.investType.${d.type}'.tr()),
            if (!defs.any((d) => d.type == _type)) (_type, 'form.investType.$_type'.tr()),
          ],
          onChanged: (v) => setState(() => _type = v),
        ),
        if (description != null && description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(description, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, height: 1.35)),
          ),
        pkText(controller: _name, label: 'form.name'.tr(), validator: _req),
        for (final f in def.fields) _fieldWidget(f, lang),
        // Savings circle: worked out from the contribution and members; typing a payout
        // in the field above replaces it.
        if (def.estimate != null)
          _Worked(
            label: def.estimate!.label(lang),
            value: def.estimatePayout(_numbers(def)) == null ? '-' : _money(def.estimatePayout(_numbers(def))!),
          ),
        if (def.derivesAmountInvested)
          _Worked(
            label: 'investForm.amountInvestedWorked'.tr(),
            value: derived.invested == null ? '-' : _money(derived.invested!),
          )
        else
          pkMoney(controller: _amount, label: 'form.amountInvested'.tr()),
        if (def.derivesValue)
          _Worked(
            label: 'investForm.currentValueWorked'.tr(),
            value: derived.value == null
                ? (derived.invested == null ? '-' : _money(derived.invested!))
                : _money(derived.value!),
          )
        else
          pkMoney(controller: _value, label: 'form.currentValue'.tr(), required: false),
        pkDropdown<String>(value: _status, label: 'form.status'.tr(), entries: _entries(_investStatuses, 'form.investStatus'), onChanged: (v) => setState(() => _status = v)),
        if (def.interest) ...[
          pkText(controller: _return, label: 'form.expectedReturn'.tr(), keyboard: const TextInputType.numberWithOptions(decimal: true)),
          pkDropdown<String>(value: _interestPeriod, label: 'form.interestPeriod'.tr(), entries: _entries(_interestPeriods, 'form.interestPeriods'), onChanged: (v) => setState(() => _interestPeriod = v)),
        ],
        pkDate(context: context, label: 'form.startedAt'.tr(), value: _startedAt, onPick: (d) => setState(() => _startedAt = d)),
        if (def.requiresMaturity)
          pkDate(context: context, label: 'form.maturityDate'.tr(), value: _maturity, onPick: (d) => setState(() => _maturity = d), required: true),
        if (def.reminders.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('investForm.remindMe'.tr(), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(_reminderHint(def), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, height: 1.35)),
              value: _remind,
              onChanged: (v) => setState(() => _remind = v),
            ),
          ),
        pkText(controller: _notes, label: 'form.notes'.tr(), maxLines: 2),
      ],
    );
  }

  /// What the reminders cover for this kind of holding, in words.
  String _reminderHint(InvestmentTypeDef def) {
    final parts = [for (final r in def.reminders) 'investForm.remind_$r'.tr()];
    return parts.join(' ');
  }
}

/// A figure the app works out from what was typed, shown instead of asking for it.
class _Worked extends StatelessWidget {
  const _Worked({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13))),
          const SizedBox(width: 12),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- Project -------

class ProjectForm extends ConsumerStatefulWidget {
  const ProjectForm({super.key, this.item});
  final ProjectItem? item;

  @override
  ConsumerState<ProjectForm> createState() => _ProjectFormState();
}

class _ProjectFormState extends ConsumerState<ProjectForm> with _FormSubmit {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _description = TextEditingController(text: widget.item?.description ?? '');
  late final _budget = TextEditingController(
      text: widget.item?.budget == null ? '' : _major(widget.item!.budget!).toStringAsFixed(0));
  late String _status = widget.item?.status ?? 'active';
  late DateTime? _targetDate = apiToDate(widget.item?.targetDate);

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _budget.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final data = <String, dynamic>{'name': _name.text.trim(), 'status': _status};
    if (_description.text.trim().isNotEmpty) data['description'] = _description.text.trim();
    if (_budget.text.trim().isNotEmpty) data['budget'] = double.parse(_budget.text.trim());
    if (_targetDate != null) data['target_date'] = dateToApi(_targetDate);

    final repo = ref.read(planRepositoryProvider);
    submit(ref, () => widget.item == null ? repo.createProject(data) : repo.updateProject(widget.item!.id, data), projectsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final edit = widget.item != null;
    return _Scaffold(
      title: edit ? 'form.editProject'.tr() : 'form.newProject'.tr(),
      formKey: _formKey,
      loading: loading,
      onSave: _save,
      saveLabel: edit ? 'form.save'.tr() : 'form.create'.tr(),
      children: [
        pkText(controller: _name, label: 'form.name'.tr(), validator: _req),
        pkText(controller: _description, label: 'form.description'.tr(), maxLines: 2),
        pkDropdown<String>(value: _status, label: 'form.status'.tr(), entries: _entries(_projectStatuses, 'form.projectStatus'), onChanged: (v) => setState(() => _status = v)),
        pkMoney(controller: _budget, label: 'form.budget'.tr(), required: false),
        pkDate(context: context, label: 'form.targetDate'.tr(), value: _targetDate, onPick: (d) => setState(() => _targetDate = d)),
      ],
    );
  }
}

// --------------------------------------------------------- Action sheets -----

/// Bottom sheet: add a contribution to [goalId].
Future<void> showContributeSheet(BuildContext context, WidgetRef ref, String goalId) =>
    _amountSheet(
      context,
      ref,
      title: 'form.contribute'.tr(),
      action: (data) => ref.read(planRepositoryProvider).contributeGoal(goalId, data),
      listProvider: goalsProvider,
      dateKey: 'contributed_at',
      dateLabel: 'form.contributedAt'.tr(),
      extraInvalidate: (r) => r.invalidate(goalContributionsProvider(goalId)),
    );

/// Bottom sheet: edit a contribution.
Future<void> showEditContributionSheet(
  BuildContext context,
  WidgetRef ref,
  String goalId,
  GoalContribution contribution,
) =>
    _amountSheet(
      context,
      ref,
      title: 'form.editContribution'.tr(),
      action: (data) => ref.read(planRepositoryProvider).updateGoalContribution(goalId, contribution.id, data),
      listProvider: goalsProvider,
      dateKey: 'contributed_at',
      dateLabel: 'form.contributedAt'.tr(),
      extraInvalidate: (r) => r.invalidate(goalContributionsProvider(goalId)),
      initialAmount: contribution.amount.amount,
      initialNote: contribution.note,
      initialDate: contribution.contributedAt,
    );

/// Bottom sheet: record a repayment for [loanId].
Future<void> showRepaySheet(BuildContext context, WidgetRef ref, String loanId) =>
    _amountSheet(
      context,
      ref,
      title: 'form.repay'.tr(),
      action: (data) => ref.read(planRepositoryProvider).repayLoan(loanId, data),
      listProvider: loansProvider,
      dateKey: 'paid_at',
      dateLabel: 'form.paidAt'.tr(),
      extraInvalidate: (r) => r.invalidate(loanRepaymentsProvider(loanId)),
    );

/// Bottom sheet: edit a repayment.
Future<void> showEditRepaymentSheet(
  BuildContext context,
  WidgetRef ref,
  String loanId,
  LoanRepayment repayment,
) =>
    _amountSheet(
      context,
      ref,
      title: 'form.editRepayment'.tr(),
      action: (data) => ref.read(planRepositoryProvider).updateLoanRepayment(loanId, repayment.id, data),
      listProvider: loansProvider,
      dateKey: 'paid_at',
      dateLabel: 'form.paidAt'.tr(),
      extraInvalidate: (r) => r.invalidate(loanRepaymentsProvider(loanId)),
      initialAmount: repayment.amount.amount,
      initialNote: repayment.note,
      initialDate: repayment.paidAt,
    );

Future<void> _amountSheet(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required Future<void> Function(Map<String, dynamic>) action,
  required ProviderOrFamily listProvider,
  required String dateKey,
  required String dateLabel,
  void Function(WidgetRef)? extraInvalidate,
  double? initialAmount,
  String? initialNote,
  String? initialDate,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      // Lift above the keyboard and the system navigation bar, and scroll when
      // the form is taller than what is left on small screens.
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 4,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
        ),
        child: _AmountSheetBody(
          title: title, action: action, listProvider: listProvider,
          dateKey: dateKey, dateLabel: dateLabel, ref: ref,
          extraInvalidate: extraInvalidate,
          initialAmount: initialAmount,
          initialNote: initialNote,
          initialDate: initialDate,
        ),
      ),
    ),
  );
}

class _AmountSheetBody extends StatefulWidget {
  const _AmountSheetBody({
    required this.title,
    required this.action,
    required this.listProvider,
    required this.dateKey,
    required this.dateLabel,
    required this.ref,
    this.extraInvalidate,
    this.initialAmount,
    this.initialNote,
    this.initialDate,
  });

  final String title;
  final Future<void> Function(Map<String, dynamic>) action;
  final ProviderOrFamily listProvider;
  final String dateKey;
  final String dateLabel;
  final WidgetRef ref;
  final void Function(WidgetRef)? extraInvalidate;
  final double? initialAmount;
  final String? initialNote;
  final String? initialDate;

  @override
  State<_AmountSheetBody> createState() => _AmountSheetBodyState();
}

class _AmountSheetBodyState extends State<_AmountSheetBody> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: widget.initialAmount != null ? widget.initialAmount!.toStringAsFixed(0) : '',
  );
  late final _note = TextEditingController(text: widget.initialNote ?? '');
  DateTime? _date;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialDate != null) {
      _date = apiToDate(widget.initialDate);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final data = <String, dynamic>{'amount': double.parse(_amount.text.trim())};
    if (_note.text.trim().isNotEmpty) data['note'] = _note.text.trim();
    if (_date != null) data[widget.dateKey] = dateToApi(_date);
    try {
      await widget.action(data);
      widget.ref.invalidate(widget.listProvider);
      widget.ref.invalidate(dashboardProvider);
      if (widget.extraInvalidate != null) {
        widget.extraInvalidate!(widget.ref);
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('form.saved'.tr())));
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.displayMessage)));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          ),
          const SizedBox(height: 16),
          pkMoney(controller: _amount, label: 'form.amount'.tr()),
          pkText(controller: _note, label: 'form.note'.tr()),
          pkDate(context: context, label: widget.dateLabel, value: _date, onPick: (d) => setState(() => _date = d)),
          pkSubmit(loading: _loading, label: 'form.save'.tr(), onPressed: _submit),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- shared ------

String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'auth.required'.tr() : null;

class _Scaffold extends StatelessWidget {
  const _Scaffold({
    required this.title,
    required this.formKey,
    required this.loading,
    required this.onSave,
    required this.saveLabel,
    required this.children,
  });

  final String title;
  final GlobalKey<FormState> formKey;
  final bool loading;
  final VoidCallback onSave;
  final String saveLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...children,
                const SizedBox(height: 8),
                pkSubmit(loading: loading, label: saveLabel, onPressed: onSave),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
