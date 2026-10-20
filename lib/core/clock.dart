import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the app reads the current time.
///
/// A provider rather than a bare `DateTime.now()` so the clock on the home
/// screen can be pinned in tests and in the review screenshots. A screenshot
/// whose clock moves every run is a screenshot nobody can diff.
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);
