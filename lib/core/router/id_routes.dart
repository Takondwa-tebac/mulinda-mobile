import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';

import '../../features/plan/data/bill_models.dart';
import '../../features/plan/data/plan_models.dart';
import '../../features/plan/data/plan_repository.dart';
import '../../features/plan/screens/bill_detail_screen.dart';
import '../../features/plan/screens/goal_detail_screen.dart';
import '../../features/plan/screens/investment_detail_screen.dart';
import '../../features/plan/screens/plan_detail_screens.dart';
import '../../features/summary/screens/daily_summary_detail_screen.dart';
import '../../features/transactions/screens/transaction_detail_screen.dart';
import '../widgets/by_id_loader.dart';
import 'routes.dart';

/// Detail routes addressed by id (`/budgets/:id` …). Each one uses the object
/// passed as `extra` when there is one, and otherwise loads the item; a
/// deleted or forbidden item goes back to its list with a message.
List<GoRoute> idDetailRoutes() => [
  GoRoute(
    path: Routes.budgetByIdPath,
    builder: (_, s) => ByIdLoader<BudgetItem>(
      id: s.pathParameters['id']!,
      initial: s.extra is BudgetItem ? s.extra! as BudgetItem : null,
      load: (ref, id) => ref.read(planRepositoryProvider).budget(id),
      builder: (b) => BudgetDetailScreen(budget: b),
      listRoute: Routes.budgets,
      title: 'plan.budgets'.tr(),
    ),
  ),
  GoRoute(
    path: Routes.loanByIdPath,
    builder: (_, s) => ByIdLoader<LoanItem>(
      id: s.pathParameters['id']!,
      initial: s.extra is LoanItem ? s.extra! as LoanItem : null,
      load: (ref, id) => ref.read(planRepositoryProvider).loan(id),
      builder: (l) => LoanDetailScreen(loan: l),
      listRoute: Routes.loans,
      title: 'plan.loans'.tr(),
    ),
  ),
  GoRoute(
    path: Routes.goalByIdPath,
    builder: (_, s) => ByIdLoader<GoalItem>(
      id: s.pathParameters['id']!,
      initial: s.extra is GoalItem ? s.extra! as GoalItem : null,
      load: (ref, id) => ref.read(planRepositoryProvider).goal(id),
      builder: (g) => GoalDetailScreen(goal: g),
      listRoute: Routes.goals,
      title: 'plan.goals'.tr(),
    ),
  ),
  GoRoute(
    path: Routes.investmentByIdPath,
    builder: (_, s) => ByIdLoader<InvestmentItem>(
      id: s.pathParameters['id']!,
      initial: s.extra is InvestmentItem ? s.extra! as InvestmentItem : null,
      load: (ref, id) => ref.read(planRepositoryProvider).investment(id),
      builder: (i) => InvestmentDetailScreen(investment: i),
      listRoute: Routes.investments,
      title: 'plan.investments'.tr(),
    ),
  ),
  GoRoute(
    path: Routes.billByIdPath,
    builder: (_, s) => ByIdLoader<Bill>(
      id: s.pathParameters['id']!,
      initial: s.extra is Bill ? s.extra! as Bill : null,
      load: (ref, id) => ref.read(planRepositoryProvider).bill(id),
      builder: (b) => BillDetailScreen(bill: b),
      listRoute: Routes.plan,
      title: 'bills.title'.tr(),
    ),
  ),
  GoRoute(
    path: Routes.dailySummaryByIdPath,
    builder: (_, s) => DailySummaryDetailScreen.byId(summaryId: s.pathParameters['id']!),
  ),
  GoRoute(
    path: Routes.transactionByIdPath,
    builder: (_, s) => TransactionDetailScreen(txnId: s.pathParameters['id']!),
  ),
];
