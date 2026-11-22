import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The current time, overridable in tests (date-dependent cards on Home).
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
