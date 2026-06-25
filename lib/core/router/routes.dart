/// Centralised route paths.
abstract class Routes {
  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';

  static const incomeSetup = '/income-setup';

  static const home = '/home';
  static const activity = '/activity';
  static const plan = '/plan';
  static const profile = '/profile';
  static const editProfile = '/edit-profile';

  static const coach = '/coach';
  static const insights = '/insights';

  // Capture / activity
  static const addTransaction = '/add-transaction';
  static const addAccount = '/add-account';
  static const pasteSms = '/paste-sms';
  static const scanReceipt = '/scan-receipt';
  static const inbox = '/inbox';

  // Plan domain lists
  static const goals = '/goals';
  static const budgets = '/budgets';
  static const loans = '/loans';
  static const investments = '/investments';
  static const projects = '/projects';

  // Transaction detail
  static const transactionDetail = '/transaction-detail';

  // Goal detail (item passed via GoRouter `extra`)
  static const goalDetail = '/goal-detail';

  // Plan create/edit forms (item passed via GoRouter `extra`)
  static const goalForm = '/goal-form';
  static const budgetForm = '/budget-form';
  static const loanForm = '/loan-form';
  static const investmentForm = '/investment-form';
  static const projectForm = '/project-form';

  // Admin (visible only to admin / super-admin users)
  static const admin = '/admin';
  static const adminNotification = '/admin/notification';
  static const adminUsers = '/admin/users';
  static const adminAudit = '/admin/audit';
}
