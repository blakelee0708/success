import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/app_category.dart';
import '../../../domain/launcher_app.dart';
import '../../launcher/presentation/widgets/category_picker.dart';
import '../../launcher/presentation/widgets/contact_dialog.dart';
import '../application/guardian_home_apps_controller.dart';
import 'widgets/guardian_surfaces.dart';

/// Widget keys the tests drive.
class GuardianLauncherKeys {
  GuardianLauncherKeys._();

  static const empty = Key('guardian-launcher-empty');
  static const list = Key('guardian-launcher-list');
  static const add = Key('guardian-launcher-add');

  static Key rename(String id) => Key('guardian-launcher-rename-$id');
  static Key colour(String id) => Key('guardian-launcher-colour-$id');
  static Key delete(String id) => Key('guardian-launcher-delete-$id');
}

/// 홈 화면 — the buttons on the parent's launcher, edited from here.
///
/// This is the feature the guardian half exists for. Until Phase 4 it drew the
/// guardian's own local settings, which meant the card's promise that a change
/// reaches the parent's phone was not true. It now reads and writes the
/// parent's `home_apps` rows.
class GuardianLauncherTab extends ConsumerWidget {
  const GuardianLauncherTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(selectedSeniorProfileProvider);
    final apps = ref.watch(guardianHomeAppsProvider);

    if (profile == null) {
      return const _Message(
        key: GuardianLauncherKeys.empty,
        title: '아직 연결된 부모님이 없어요',
        detail:
            '가족 탭에서 부모님을 추가하고 연결 번호를 알려 드리면,\n'
            '여기에서 홈 화면을 정리해 드릴 수 있어요.',
      );
    }

    return switch (apps) {
      AsyncError(:final error) => _Message(
        title: '홈 화면을 불러오지 못했어요',
        detail: '$error',
        onRetry: () => ref.invalidate(guardianHomeAppsProvider),
      ),
      AsyncData(:final value) => _Editor(
        profile: profile.displayName,
        apps: value,
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _Editor extends ConsumerWidget {
  const _Editor({required this.profile, required this.apps});

  final String profile;
  final List<LauncherApp> apps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One scroll view holds the whole tab — heading, rows and 버튼 추가하기.
    //
    // The heading used to sit above the list and the button was pinned to the
    // bottom of the screen, which put a field of nothing between the last row
    // and the button and said nothing about where a new button would land. In
    // the list, 버튼 추가하기 is simply the next thing after the last button,
    // and adding one pushes it down.
    return ReorderableListView(
      key: GuardianLauncherKeys.list,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(
          0,
          GuardianHeading.crown,
          0,
          GuardianHeading.gap,
        ),
        child: GuardianHeading(
          title: '$profile 홈 화면',
          lede:
              '바꾸면 부모님 폰에 반영됩니다. '
              '부모님 폰이 꺼져 있으면 다음에 켤 때 적용돼요.',
        ),
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (apps.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: _Message(
                title: '아직 버튼이 없어요',
                detail: '아래에서 버튼을 추가하면 부모님 홈 화면에 나타납니다.',
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: GuardianPrimaryButton(
              key: GuardianLauncherKeys.add,
              label: '버튼 추가하기',
              icon: Icons.add_rounded,
              onPressed: () => _add(context, ref),
            ),
          ),
        ],
      ),
      onReorder: (oldIndex, newIndex) =>
          _run(context, ref, (c) => c.reorder(oldIndex, newIndex)),
      children: [
        for (final app in apps)
          _AppRow(
            key: ValueKey(app.id),
            app: app,
            onRename: () => _rename(context, ref, app),
            onRecolour: () => _recolour(context, ref, app),
            onDelete: () => _confirmDelete(context, ref, app),
          ),
      ],
    );
  }

  /// Every edit reports its own failure. The write goes to someone else's
  /// phone, so "it looked like it worked" is not good enough.
  static Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<bool> Function(GuardianHomeAppsController) action,
  ) async {
    final ok = await action(ref.read(guardianHomeAppsProvider.notifier));
    if (ok || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('바꾸지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요.')),
      );
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    LauncherApp app,
  ) async {
    if (app.category.isContact) {
      final draft = await askForContact(
        context,
        title: '고치기',
        initialName: app.label,
        initialNumber: app.phoneNumber ?? '',
      );
      if (draft == null || !context.mounted) return;
      await _run(
        context,
        ref,
        (c) => c.editContact(
          app.id,
          label: draft.name,
          phoneNumber: draft.number,
        ),
      );
      return;
    }

    final name = await _askForName(
      context,
      title: '이름 바꾸기',
      initial: app.label,
    );
    if (name == null || !context.mounted) return;
    await _run(context, ref, (c) => c.rename(app.id, name));
  }

  /// The kind comes first, then the name.
  ///
  /// The picker draws the parent's own tiles rather than this half's cards:
  /// the guardian is choosing what will appear on their mother's home screen,
  /// so what they are shown is that button, not a form control.
  Future<void> _add(BuildContext context, WidgetRef ref) async {
    // 폰에 있는 앱 **is** offered here, and it means something different from
    // what it means on the parent's phone. The guardian is not shown the list
    // of what is installed — that list never leaves their parent's handset —
    // so what they place is an empty slot. Their parent presses it once and
    // picks from their own phone.
    //
    // That split is the whole of 경로 2: the guardian does the part their
    // parent cannot (knowing a button should exist, and putting it on the
    // home screen) and the parent does the part only they can (choosing from
    // a list only their phone can see).
    final category = await askForCategory(
      context,
      alreadyOn: ref.read(guardianHomeAppsProvider).value ?? const [],
    );
    if (category == null || !context.mounted) return;

    // Nothing to ask. Naming it would be naming an app nobody has chosen,
    // and the label becomes the app's own name the moment they do.
    if (category == AppCategory.installed) {
      await _run(
        context,
        ref,
        (c) => c.add(label: '눌러서 앱 고르기', category: category),
      );
      return;
    }

    // A person needs a number as well as a name. This is the screen it is
    // meant to be typed on: the guardian knows the number, the parent does
    // not have to, and their phone never reads an address book.
    if (category.isContact) {
      final draft = await askForContact(context);
      if (draft == null || !context.mounted) return;
      await _run(
        context,
        ref,
        (c) => c.add(
          label: draft.name,
          category: category,
          phoneNumber: draft.number,
        ),
      );
      return;
    }

    final name = await _askForName(
      context,
      title: '버튼 추가하기',
      initial: category.defaultLabel,
    );
    if (name == null || !context.mounted) return;
    await _run(context, ref, (c) => c.add(label: name, category: category));
  }

  Future<void> _recolour(
    BuildContext context,
    WidgetRef ref,
    LauncherApp app,
  ) async {
    final chosen = await showDialog<_ColourChoice>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('버튼 색'),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final colour in ButtonColor.values)
                  GestureDetector(
                    onTap: () => Navigator.pop(context, _ColourChoice(colour)),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colour.color,
                        border: Border.all(
                          color: app.color == colour
                              ? AppColors.guardianPrimary
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, const _ColourChoice(null)),
            child: const Text('원래 색으로'),
          ),
        ],
      ),
    );
    if (chosen == null || !context.mounted) return;
    await _run(context, ref, (c) => c.setColor(app.id, chosen.colour));
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    LauncherApp app,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${app.label} 버튼을 지울까요?'),
        content: const Text('부모님 홈 화면에서 사라집니다. 나중에 다시 추가할 수 있어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('그만두기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('지우기'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(context, ref, (c) => c.remove(app.id));
  }

  static Future<String?> _askForName(
    BuildContext context, {
    required String title,
    required String initial,
  }) => showDialog<String>(
    context: context,
    builder: (context) => _NameDialog(title: title, initial: initial),
  );
}

/// Wraps the nullable colour so "원래 색으로" can be told from a dismissed
/// dialog — both would otherwise arrive as null.
class _ColourChoice {
  const _ColourChoice(this.colour);

  final ButtonColor? colour;
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '버튼 이름',
          hintText: '어르신이 알아보실 이름으로',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('그만두기'),
        ),
        TextButton(
          onPressed: () {
            final name = _controller.text.trim();
            if (name.isNotEmpty) Navigator.pop(context, name);
          },
          child: const Text('저장'),
        ),
      ],
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    super.key,
    required this.app,
    required this.onRename,
    required this.onRecolour,
    required this.onDelete,
  });

  final LauncherApp app;
  final VoidCallback onRename;
  final VoidCallback onRecolour;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GuardianCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: app.baseColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(app.category.icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextButton(
                key: GuardianLauncherKeys.rename(app.id),
                // A slot nobody has filled in cannot be renamed: the name is
                // whatever app the parent picks, and writing one now would
                // only be a label that turns into a lie.
                onPressed: app.awaitingChoice ? null : onRename,
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.zero,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      app.awaitingChoice ? '앱 버튼' : app.label,
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: AppColors.guardianInk,
                      ),
                    ),
                    // Says where the ball is. The guardian placed this and
                    // nothing more will happen until their parent presses it,
                    // and a row that did not say so would read as broken.
                    if (app.awaitingChoice)
                      const Text(
                        '부모님이 폰에서 고르시면 이름이 나와요',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          color: AppColors.guardianInkFaint,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            IconButton(
              key: GuardianLauncherKeys.colour(app.id),
              onPressed: onRecolour,
              icon: const Icon(Icons.palette_outlined),
              color: AppColors.guardianInkSoft,
              tooltip: '색 바꾸기',
            ),
            IconButton(
              key: GuardianLauncherKeys.delete(app.id),
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              color: AppColors.guardianInkSoft,
              tooltip: '지우기',
            ),
            // Was #9C8770 — the muted clay that came out of the senior palette
            // with the rest of the beige, and had no business on this half
            // either.
            const Icon(Icons.drag_handle, color: AppColors.guardianInkDisabled),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    super.key,
    required this.title,
    required this.detail,
    this.onRetry,
  });

  final String title;
  final String detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: AppColors.guardianInk,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                color: AppColors.guardianInkFaint,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
            ],
          ],
        ),
      ),
    );
  }
}
