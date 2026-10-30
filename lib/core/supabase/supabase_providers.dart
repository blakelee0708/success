import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../data/remote/app_config_repository.dart';
import '../../data/remote/guardian_auth_repository.dart';
import '../../data/remote/home_apps_repository.dart';
import '../../data/remote/message_repository.dart';
import '../../data/remote/pairing_repository.dart';
import '../../data/remote/senior_link_repository.dart';
import '../../data/remote/subscription_repository.dart';
import 'senior_auth.dart';
import 'supabase_config.dart';

/// The build's Supabase settings. Overridden in tests that need to pretend a
/// project is configured without one existing.
final supabaseConfigProvider = Provider<SupabaseConfig>(
  (ref) => SupabaseConfig.fromEnvironment,
);

/// The initialised client, or null when the build carries no keys.
///
/// Reading `Supabase.instance` before `Supabase.initialize` throws, so this
/// asks the config first rather than catching the failure — a launcher must
/// not depend on an exception path to draw its home screen.
final supabaseClientProvider = Provider<sb.SupabaseClient?>((ref) {
  if (!ref.watch(supabaseConfigProvider).isConfigured) return null;
  return sb.Supabase.instance.client;
});

/// The parent's phone's session. Anonymous, because the senior is never asked
/// to make an account — and required, because every senior-side database
/// function refuses a caller with no `auth.uid()`.
///
/// It is read only on the senior's own paths. Signing in at start-up instead
/// would hand the guardian's phone an anonymous session before they reach
/// their own sign-in screen, which is a session that looks like one to
/// anything asking whether somebody is signed in.
final seniorAuthProvider = Provider<SeniorAuth>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const OpenSeniorAuth();
  return SupabaseSeniorAuth(client);
});

/// Each repository resolves to its Supabase implementation when the app has a
/// project, and to the in-memory twin when it does not. Nothing above this
/// layer knows which one it got, so every screen built in Phases 1–3 keeps
/// working on a build with no backend.
final guardianAuthRepositoryProvider = Provider<GuardianAuthRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  // No confirmation step in the fallback: with no project there is no mail to
  // confirm, and Phase 3 requires the dashboard stay reachable with no backend.
  if (client == null) {
    return InMemoryGuardianAuthRepository(confirmationRequired: false);
  }
  return SupabaseGuardianAuthRepository(client);
});

final seniorLinkRepositoryProvider = Provider<SeniorLinkRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return InMemorySeniorLinkRepository();
  return SupabaseSeniorLinkRepository(client);
});

/// The pairing twin shares the link repository's state, so a code redeemed in
/// a build with no project still shows up as a linked parent everywhere else.
final pairingRepositoryProvider = Provider<PairingRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) {
    final links = ref.watch(seniorLinkRepositoryProvider);
    return InMemoryPairingRepository(links as InMemorySeniorLinkRepository);
  }
  return SupabasePairingRepository(client);
});

/// Shares the link repository's state for the same reason the pairing twin
/// does: consent is recorded on the profile the rest of the app reads.
final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) {
    final links = ref.watch(seniorLinkRepositoryProvider);
    return InMemorySubscriptionRepository(
      links as InMemorySeniorLinkRepository,
    );
  }
  return SupabaseSubscriptionRepository(client);
});

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) {
    return InMemoryMessageRepository(
      ref.watch(seniorLinkRepositoryProvider) as InMemorySeniorLinkRepository,
      subscriptions:
          ref.watch(subscriptionRepositoryProvider)
              as InMemorySubscriptionRepository,
    );
  }
  return SupabaseMessageRepository(client);
});

final homeAppsRepositoryProvider = Provider<HomeAppsRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return InMemoryHomeAppsRepository();
  return SupabaseHomeAppsRepository(client);
});

final appConfigRepositoryProvider = Provider<AppConfigRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return InMemoryAppConfigRepository();
  return SupabaseAppConfigRepository(client);
});

/// Read once per run. A setting that changes once, on launch day, does not
/// need a poll.
final appConfigProvider = FutureProvider<AppConfig>(
  (ref) => ref.watch(appConfigRepositoryProvider).read(),
);
