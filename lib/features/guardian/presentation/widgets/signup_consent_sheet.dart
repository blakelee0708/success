import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/signup_consent.dart';
import 'guardian_surfaces.dart';

/// Where the pages the sheet links to live. The same host the reset mail
/// points at, which `privacy_policy_test` already pins.
const termsUrl = 'https://app.jalboine.com/terms.html';
const privacyUrl = 'https://app.jalboine.com/privacy.html';

/// 약관 동의, asked once before an account can exist.
///
/// It replaced one grey line reading 시작하면 ... 동의하게 됩니다 - text, not
/// a link, naming a 이용약관 that did not exist. 개인정보보호법 asks for an
/// act rather than a passage: itemised, 필수 and 선택 apart, each readable
/// before it is agreed to.
///
/// **Three rules shape it, and each exists because its opposite is common:**
///
/// - 전체 동의 ticks the optional item too, which is why it is drawn apart
///   from the list and above a rule rather than as a fourth row. A master
///   switch standing level with the items it controls is how a 선택 item
///   gets taken without being read.
/// - **보기 opens the page and does not tick the box.** Reading is not
///   agreeing, and a link that agrees on your behalf is the pattern this
///   screen exists to replace.
/// - 시작하기 is disabled until both 필수 items are ticked, and it is
///   visibly disabled. A button that looks pressable and refuses teaches
///   people to press harder rather than to read.
class SignupConsentSheet extends ConsumerStatefulWidget {
  const SignupConsentSheet({super.key});

  static const sheetKey = Key('signup-consent-sheet');
  static const allKey = Key('signup-consent-all');
  static const termsKey = Key('signup-consent-terms');
  static const privacyKey = Key('signup-consent-privacy');
  static const marketingKey = Key('signup-consent-marketing');
  static const continueKey = Key('signup-consent-continue');
  static const termsLinkKey = Key('signup-consent-terms-link');
  static const privacyLinkKey = Key('signup-consent-privacy-link');

  /// Shows the sheet unless this phone has already agreed to this version.
  ///
  /// Returns true when the caller may go on. **Dismissing it is a no**, so a
  /// swipe down does not hand anybody an account.
  static Future<bool> ensure(BuildContext context, WidgetRef ref) async {
    if (await ref.read(signupConsentStoreProvider).load() case final had?) {
      if (had.version == signupConsentVersion) return true;
    }
    if (!context.mounted) return false;
    final agreed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // The sheet is pushed onto the root navigator, outside the `Theme`
      // the dashboard wraps its subtree in - but this one opens from the
      // start screen, which runs on the senior theme. Named so the sheet is
      // the guardian's blue either way.
      builder: (_) => Theme(
        data: AppTheme.guardian,
        child: const SignupConsentSheet(key: SignupConsentSheet.sheetKey),
      ),
    );
    return agreed ?? false;
  }

  @override
  ConsumerState<SignupConsentSheet> createState() =>
      _SignupConsentSheetState();
}

class _SignupConsentSheetState extends ConsumerState<SignupConsentSheet> {
  bool _terms = false;
  bool _privacy = false;
  bool _marketing = false;

  bool get _required => _terms && _privacy;
  bool get _all => _required && _marketing;

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on Object {
      // A phone with no browser, which is not a reason to block the sheet.
      // The pages are also reachable from the store listing.
    }
  }

  Future<void> _agree() async {
    await ref.read(signupConsentStoreProvider).save(
      SignupConsent(
        version: signupConsentVersion,
        agreedAt: DateTime.now(),
        marketing: _marketing,
      ),
    );
    ref.invalidate(signupConsentProvider);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '잘보이네를 시작하기 전에',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: AppColors.guardianInk,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '아래 내용을 확인하고 동의해 주세요. 각 항목은 보기를 눌러 전문을 읽으실 수 있어요.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: AppColors.guardianInkFaint,
                ),
              ),
              const SizedBox(height: 16),
              // Above the rule, not level with the items: a master switch
              // standing among the things it controls is how a 선택 item
              // gets agreed to without being read.
              _Row(
                rowKey: SignupConsentSheet.allKey,
                label: '전체 동의',
                bold: true,
                checked: _all,
                onChanged: (on) => setState(() {
                  _terms = on;
                  _privacy = on;
                  _marketing = on;
                }),
              ),
              const Divider(height: 18, color: AppColors.guardianRule),
              _Row(
                rowKey: SignupConsentSheet.termsKey,
                label: '[필수] 서비스 이용약관',
                checked: _terms,
                onChanged: (on) => setState(() => _terms = on),
                linkKey: SignupConsentSheet.termsLinkKey,
                onOpen: () => _open(termsUrl),
              ),
              _Row(
                rowKey: SignupConsentSheet.privacyKey,
                label: '[필수] 개인정보 수집·이용',
                checked: _privacy,
                onChanged: (on) => setState(() => _privacy = on),
                linkKey: SignupConsentSheet.privacyLinkKey,
                onOpen: () => _open(privacyUrl),
              ),
              _Row(
                rowKey: SignupConsentSheet.marketingKey,
                label: '[선택] 새 소식과 혜택 받기',
                checked: _marketing,
                onChanged: (on) => setState(() => _marketing = on),
              ),
              const SizedBox(height: 14),
              GuardianPrimaryButton(
                key: SignupConsentSheet.continueKey,
                label: '동의하고 시작하기',
                icon: Icons.arrow_forward_rounded,
                onPressed: _required ? _agree : null,
              ),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '선택 항목에 동의하지 않으셔도 잘보이네를 쓰실 수 있어요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.guardianInkFaint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.rowKey,
    required this.label,
    required this.checked,
    required this.onChanged,
    this.bold = false,
    this.linkKey,
    this.onOpen,
  });

  final Key rowKey;
  final String label;
  final bool checked;
  final ValueChanged<bool> onChanged;
  final bool bold;
  final Key? linkKey;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            key: rowKey,
            onTap: () => onChanged(!checked),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    checked
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    size: 22,
                    color: checked
                        ? AppColors.guardianPrimary
                        : AppColors.guardianInkDisabled,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: bold ? 15 : 14,
                        fontWeight: bold
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: AppColors.guardianInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Opens the page and **does not tick the box**. Reading is not
        // agreeing, and a link that agrees on your behalf is the pattern
        // this sheet exists to replace.
        if (onOpen case final open?)
          TextButton(
            key: linkKey,
            onPressed: open,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              '보기',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
      ],
    );
  }
}
