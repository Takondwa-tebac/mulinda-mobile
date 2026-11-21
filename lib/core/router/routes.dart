/// Centralised route paths.
abstract class Routes {
  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';

  static const incomeSetup = '/income-setup';
  static const permissions = '/permissions';
  static const legal = '/legal';

  static const home = '/home';
  static const activity = '/activity';
  static const plan = '/plan';
  static const profile = '/profile';
  static const editProfile = '/edit-profile';
  static const preferences = '/preferences';
  static const personalData = '/personal-data';

  static const coach = '/coach';
  static const insights = '/insights';
  static const offlineSync = '/offline-sync';
  static const notificationDetail = '/notifications/:id';
  static String notificationDetailFor(String id) => '/notifications/$id';

  // Capture / activity
  static const addTransaction = '/add-transaction';
  static const addAccount = '/add-account';
  static const accountDetail = '/account-detail';
  static const pasteSms = '/paste-sms';
  static const scanReceipt = '/scan-receipt';
  static const inbox = '/inbox';
  static const bulkSmsImport = '/bulk-sms-import';
  static const manualSmsScan = '/manual-sms-scan';
  static const review = '/review';
  static const exports = '/exports';
  static const dailySummaries = '/daily-summaries';

  // Plan domain lists
  static const goals = '/goals';
  static const budgets = '/budgets';
  static const loans = '/loans';
  static const investments = '/investments';
  static const projects = '/projects';

  // Transaction detail
  static const transactionDetail = '/transaction-detail';

  // Detail screens by id (notification and deep links). Each loads its item
  // when no object is passed as `extra`.
  static const budgetByIdPath = '/budgets/:id';
  static const loanByIdPath = '/loans/:id';
  static const goalByIdPath = '/goals/:id';
  static const investmentByIdPath = '/investments/:id';
  static const billByIdPath = '/bills/:id';
  static const dailySummaryByIdPath = '/daily-summaries/:id';
  static const transactionByIdPath = '/transactions/:id';
  static String budgetById(String id) => '/budgets/$id';
  static String loanById(String id) => '/loans/$id';
  static String goalById(String id) => '/goals/$id';
  static String investmentById(String id) => '/investments/$id';
  static String billById(String id) => '/bills/$id';
  static String dailySummaryById(String id) => '/daily-summaries/$id';
  static String transactionById(String id) => '/transactions/$id';

  // Detail screens (item passed via GoRouter `extra`)
  static const goalDetail = '/goal-detail';
  static const budgetDetail = '/budget-detail';
  static const loanDetail = '/loan-detail';
  static const projectDetail = '/project-detail';
  static const investmentDetail = '/investment-detail';

  // Plan create/edit forms (item passed via GoRouter `extra`)
  static const goalForm = '/goal-form';
  static const budgetForm = '/budget-form';
  static const loanForm = '/loan-form';
  static const investmentForm = '/investment-form';
  static const projectForm = '/project-form';

  // Subscriptions & billing
  static const subscription = '/subscription';
  static const receipt = '/receipt';

  // Admin (visible only to admin / super-admin users)
  static const admin = '/admin';
  static const adminNotification = '/admin/notification';
  static const adminUsers = '/admin/users';
  static const adminUserDetail = '/admin/users/:userId';
  static const adminAudit = '/admin/audit';
  static const adminAnalytics = '/admin/analytics';
  static const adminFeatures = '/admin/features';
}
