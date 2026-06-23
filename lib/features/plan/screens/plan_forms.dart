import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/network/api_exception.dart';
import '../../activity/data/activity_repository.dart' show categoriesProvider;
import '../../dashboard/data/dashboard_repository.dart';
import '../data/plan_models.dart';
import '../data/plan_repository.dart';
import '../widgets/plan_form_kit.dart';

const _goalTypes = ['emergency', 'house', 'car', 'business', 'education', 'vacation', 'custom'];
const _interestTypes = ['reducing_balance', 'flat'];
const _loanStatuses = ['active', 'paid_off', 'defaulted', 'closed'];
const _investTypes = [
  'fixed_deposit', 'treasury_bill', 'treasury_bond', 'unit_trust',
  'shares', 'pension', 'business', 'property', 'other'
];
const _investStatuses = ['active', 'matured', 'sold', 'closed'];
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
    final cats = ref.watch(categoriesProvider).maybeWhen(
          data: (c) => c.where((x) => x.kind == 'expense').toList(),
          orElse: () => [],
        );
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
          child: DropdownButtonFormField<String?>(
            initialValue: _categoryId,
            decoration: InputDecoration(labelText: 'form.category'.tr()),
            items: [
              DropdownMenuItem(value: null, child: Text('form.none'.tr())),
              ...cats.map((c) => DropdownMenuItem(value: c.id as String?, child: Text(c.name))),
            ],
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
  late DateTime _startedAt = apiToDate(widget.item?.startedAt) ?? DateTime.now();
  late DateTime? _maturity = apiToDate(widget.item?.maturityDate);

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _value.dispose();
    _return.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'type': _type,
      'status': _status,
      'amount_invested': double.parse(_amount.text.trim()),
      'started_at': dateToApi(_startedAt),
    };
    if (_value.text.trim().isNotEmpty) data['current_value'] = double.parse(_value.text.trim());
    final ret = double.tryParse(_return.text.trim());
    if (ret != null) data['expected_annual_return'] = ret / 100;
    if (_maturity != null) data['maturity_date'] = dateToApi(_maturity);
    if (_notes.text.trim().isNotEmpty) data['notes'] = _notes.text.trim();

    final repo = ref.read(planRepositoryProvider);
    submit(ref, () => widget.item == null ? repo.createInvestment(data) : repo.updateInvestment(widget.item!.id, data), investmentsListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final edit = widget.item != null;
    return _Scaffold(
      title: edit ? 'form.editInvestment'.tr() : 'form.newInvestment'.tr(),
      formKey: _formKey,
      loading: loading,
      onSave: _save,
      saveLabel: edit ? 'form.save'.tr() : 'form.create'.tr(),
      children: [
        pkText(controller: _name, label: 'form.name'.tr(), validator: _req),
        pkDropdown<String>(value: _type, label: 'form.type'.tr(), entries: _entries(_investTypes, 'form.investType'), onChanged: (v) => setState(() => _type = v)),
        pkDropdown<String>(value: _status, label: 'form.status'.tr(), entries: _entries(_investStatuses, 'form.investStatus'), onChanged: (v) => setState(() => _status = v)),
        pkMoney(controller: _amount, label: 'form.amountInvested'.tr()),
        pkMoney(controller: _value, label: 'form.currentValue'.tr(), required: false),
        pkText(controller: _return, label: 'form.expectedReturn'.tr(), keyboard: const TextInputType.numberWithOptions(decimal: true)),
        pkDate(context: context, label: 'form.startedAt'.tr(), value: _startedAt, onPick: (d) => setState(() => _startedAt = d)),
        pkDate(context: context, label: 'form.maturityDate'.tr(), value: _maturity, onPick: (d) => setState(() => _maturity = d)),
        pkText(controller: _notes, label: 'form.notes'.tr(), maxLines: 2),
      ],
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
    );

Future<void> _amountSheet(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required Future<void> Function(Map<String, dynamic>) action,
  required ProviderOrFamily listProvider,
  required String dateKey,
  required String dateLabel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 4,
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
      ),
      child: _AmountSheetBody(
        title: title, action: action, listProvider: listProvider,
        dateKey: dateKey, dateLabel: dateLabel, ref: ref,
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
  });

  final String title;
  final Future<void> Function(Map<String, dynamic>) action;
  final ProviderOrFamily listProvider;
  final String dateKey;
  final String dateLabel;
  final WidgetRef ref;

  @override
  State<_AmountSheetBody> createState() => _AmountSheetBodyState();
}

class _AmountSheetBodyState extends State<_AmountSheetBody> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime? _date;
  bool _loading = false;

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
