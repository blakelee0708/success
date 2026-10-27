import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../launcher/presentation/widgets/go_home_bar.dart';
import '../../launcher/application/senior_settings_controller.dart';
import 'conversation_view.dart';

/// 가족 메시지 on the parent's phone.
///
/// Everything is drawn a size up and the monthly counter is hidden: the
/// allowance is the guardian's to manage, the senior's own replies are never
/// counted against it, and showing an elderly person a tally of how many times
/// their family may write to them would be unkind as well as useless.
class FamilyMessageScreen extends ConsumerWidget {
  const FamilyMessageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(seniorSettingsControllerProvider).value?.fontSize;

    return Scaffold(
      appBar: AppBar(title: const Text('가족 메시지')),
      bottomNavigationBar: const SafeArea(child: GoHomeBar()),
      body: MediaQuery.withClampedTextScaling(
        minScaleFactor: scale?.scale ?? 1.0,
        maxScaleFactor: scale?.scale ?? 1.0,
        child: const ConversationView(
          title: '가족',
          large: true,
          showQuota: false,
        ),
      ),
    );
  }
}
