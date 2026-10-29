import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../application/guardian_session_controller.dart';
import 'widgets/guardian_surfaces.dart';

/// 부모님이 뭐라고 부르세요 — asked once, before anything else.
///
/// **The name was never asked for and nothing ever wrote it.** Every call to
/// `ensureGuardianAccount` passed no name, so `guardian_accounts.display_name`
/// was null for every guardian in the system and four screens fell back to
/// the literal word 보호자: the family list, the parent's 긴급 연락 tile, the
/// ring card, and the name over a message bubble when a parent has two
/// children. The connect form asks for the **parent's** name and phone; it
/// never asked for this one.
///
/// It belongs to the account rather than to a link, which is why it is here
/// and not on the connect form: a sibling joining by invite never sees that
/// form, and a family with two children is exactly where a name matters.
///
/// **Required, with no way past.** What it feeds is the sentence a senior
/// answers on their own phone - 영희님이 연결을 부탁하셨어요 - and with two
/// children a card that cannot name one is a card asking somebody to agree to
/// they-do-not-know-who.
class GuardianNameScreen extends ConsumerStatefulWidget {
  const GuardianNameScreen({super.key, required this.suggestion});

  /// What the provider called them, if it said. Only ever a suggestion.
  final String? suggestion;

  static const field = Key('guardian-name-field');
  static const save = Key('guardian-name-save');
  static const error = Key('guardian-name-error');

  @override
  ConsumerState<GuardianNameScreen> createState() => _GuardianNameScreenState();
}

class _GuardianNameScreenState extends ConsumerState<GuardianNameScreen> {
  late final _name = TextEditingController(text: widget.suggestion ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      // Not a failure: nothing failed, the form is not ready. Same shape as
      // the login screen's empty address box.
      setState(() => _error = '어머니께서 부르시는 이름을 적어 주세요.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(seniorLinkRepositoryProvider)
          .ensureGuardianAccount(displayName: name);
      ref.invalidate(guardianAccountProvider);
    } on Object {
      if (mounted) {
        setState(() => _error = '저장하지 못했어요. 인터넷 연결을 확인해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.guardianGroundEnd,
      body: GuardianGround(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              20,
              GuardianHeading.crown,
              20,
              32,
            ),
            children: [
              const GuardianHeading(title: '부모님이 뭐라고 부르세요?'),
              const SizedBox(height: GuardianHeading.gap),
              GuardianCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: GuardianNameScreen.field,
                      controller: _name,
                      enabled: !_busy,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _save(),
                      cursorColor: AppColors.guardianPrimary,
                      decoration: guardianField(
                        label: '부모님이 부르시는 이름',
                        hint: '영희, 큰아들, 막내',
                      ),
                    ),
                    const SizedBox(height: 14),
                    // **Not their legal name.** This is what their mother
                    // reads on her own phone, so 김영희님이 연결을 부탁하셨어요
                    // is the wrong answer and 영희가 is the right one - the
                    // same rule that turned the parent's own name field into
                    // 이름 또는 애칭.
                    const Text(
                      '어머니 폰에 이 이름이 그대로 보입니다.\n'
                      '메시지를 보낼 때도, 연결을 부탁할 때도요.',
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.55,
                        color: AppColors.guardianInkSoft,
                      ),
                    ),
                    if (_error case final message?) ...[
                      const SizedBox(height: 12),
                      Text(
                        message,
                        key: GuardianNameScreen.error,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: AppColors.guardianDanger,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    GuardianPrimaryButton(
                      key: GuardianNameScreen.save,
                      onPressed: _busy ? null : _save,
                      icon: Icons.check_rounded,
                      label: _busy ? '저장하는 중이에요' : '저장',
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
}
