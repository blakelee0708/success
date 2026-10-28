import 'widgets/go_home_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/app_category.dart';
import '../../../domain/launcher_app.dart';
import '../application/senior_settings_controller.dart';

import 'add_home_button.dart';
import 'widgets/contact_dialog.dart';
import 'widgets/name_dialog.dart';

abstract final class AppSettingsKeys {
  /// The way out. The ← in the corner is small, in the hardest place to
  /// reach, and a symbol rather than a word.
  static const done = GoHomeBar.buttonKey;

  static const add = Key('app-settings-add');

  /// The grip that starts a reorder. Named so a test can assert it exists:
  /// the list reorders perfectly well without it and shows nothing, which is
  /// how it shipped.
  static Key dragHandle(String id) => Key('drag-handle-$id');

  /// The three words under a button's name, and the confirm that follows
  /// 지우기. The confirm needs a key of its own because its button says
  /// 지우기 too, and a test reaching for the word now finds two.
  static Key rename(String id) => Key('rename-$id');
  static Key colour(String id) => Key('colour-$id');
  static Key delete(String id) => Key('delete-$id');
  static const deleteConfirm = Key('app-settings-delete-confirm');
}

/// 앱 설정하기 — the senior's own view of their home buttons: reorder, rename,
/// recolour, remove, add.
///
/// Deleting asks first. Everything else here is reversible by repeating it;
/// removing a button is the one action that loses something, and on this app
/// the thing lost is a button on the person's home screen.
class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(seniorSettingsControllerProvider).value?.apps ?? [];
    final controller = ref.read(seniorSettingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('앱 설정')),
      body: Column(
        children: [
          Expanded(
            child: ReorderableListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
              onReorder: controller.reorderApps,
              // In the list rather than pinned to the bottom, which is where
              // the guardian's half already puts it: pinned, it leaves a
              // field of nothing between the last row and the button and
              // says nothing about where a new button will land. Here it is
              // simply the next thing after the last one, and adding pushes
              // it down. Hollow, so it is the same object as the 추가하기
              // slot on 자세한 화면 — two ways to the same act, drawn alike.
              footer: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AddRow(onTap: () => addHomeButton(context, ref)),
                  // 가족, 소리 and 인터넷 - the three that are not apps. Below
                  // the apps rather than above them, because they are the
                  // furniture around what the senior actually chose, and in
                  // the footer rather than the list because there is exactly
                  // one of each: nothing here is reordered or deleted.
                  const _GroupTitle('이 화면에 늘 있는 버튼'),
                  for (final category in AppCategory.values)
                    if (category.fixedSlot)
                      _FixedRow(
                        app: fixedSlotApp(apps, category),
                        onRename: () => _renameFixed(context, ref, category),
                        onRecolour: () => _recolourFixed(context, ref, category),
                      ),
                  const SizedBox(height: 8),
                ],
              ),
              children: [
                for (final (index, app) in apps.indexed)
                  _AppRow(
                    key: ValueKey(app.id),
                    index: index,
                    app: app,
                    onRename: () => _rename(context, ref, app),
                    onRecolour: () => _recolour(context, ref, app),
                    onDelete: () => _confirmDelete(context, ref, app),
                  ),
              ],
            ),
          ),
          const SafeArea(
            child: GoHomeBar(
              // It says the change *already happened*, not that this button
              // does it - the difference between reassuring somebody and
              // turning the ← into the one that loses their work.
              note: '바꾸시면 바로 바뀌어요',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    LauncherApp app,
  ) async {
    // Editing a person edits both halves. A number that can only be set once
    // means a typo is fixed by deleting the button and starting again.
    if (app.category.isContact) {
      final draft = await askForContact(
        context,
        title: '고치기',
        initialName: app.label,
        initialNumber: app.phoneNumber ?? '',
      );
      if (draft == null) return;
      await ref
          .read(seniorSettingsControllerProvider.notifier)
          .editContact(app.id, label: draft.name, phoneNumber: draft.number);
      return;
    }

    final name = await askForButtonName(context, title: '이름 바꾸기', initial: app.label);
    if (name == null) return;
    await ref
        .read(seniorSettingsControllerProvider.notifier)
        .renameApp(app.id, name);
  }

  Future<void> _renameFixed(
    BuildContext context,
    WidgetRef ref,
    AppCategory category,
  ) async {
    final apps = ref.read(seniorSettingsControllerProvider).value?.apps ?? [];
    final current = fixedSlotApp(apps, category);
    final name = await askForButtonName(
      context,
      title: '이름 바꾸기',
      initial: current.label,
    );
    if (name == null) return;
    await ref
        .read(seniorSettingsControllerProvider.notifier)
        .editFixedSlot(category, label: name);
  }

  Future<void> _recolourFixed(
    BuildContext context,
    WidgetRef ref,
    AppCategory category,
  ) async {
    final apps = ref.read(seniorSettingsControllerProvider).value?.apps ?? [];
    final chosen = await _pickColour(
      context,
      current: fixedSlotApp(apps, category).color,
    );
    if (chosen == null) return;
    await ref
        .read(seniorSettingsControllerProvider.notifier)
        .editFixedSlot(category, color: chosen);
  }

  /// Shared by an app button and a fixed slot: the same circles, the same
  /// ring on the one already chosen. Null means they backed out.
  Future<ButtonColor?> _pickColour(
    BuildContext context, {
    ButtonColor? current,
  }) async {
    final chosen = await showDialog<ButtonColor?>(
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
                    onTap: () => Navigator.pop(context, colour),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colour.color,
                        border: Border.all(
                          color: current == colour
                              ? AppColors.seniorOnSurface
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return chosen;
  }

  Future<void> _recolour(
    BuildContext context,
    WidgetRef ref,
    LauncherApp app,
  ) async {
    final chosen = await _pickColour(context, current: app.color);
    if (chosen == null) return;
    await ref
        .read(seniorSettingsControllerProvider.notifier)
        .setAppColor(app.id, chosen);
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
        content: const Text('첫 화면에서 사라집니다. 나중에 다시 추가할 수 있어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('그만두기', style: TextStyle(fontSize: 20)),
          ),
          TextButton(
            key: AppSettingsKeys.deleteConfirm,
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              '지우기',
              style: TextStyle(fontSize: 20, color: AppColors.seniorSos),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(seniorSettingsControllerProvider.notifier)
        .removeApp(app.id);
  }

  /// Returns null when the senior backs out or leaves the field empty — an
  /// unnamed button is indistinguishable from every other unnamed button.
}

/// One button in the list.
///
/// **Three unlabelled symbols is what this row used to be**, right-aligned:
/// a drag handle, a painter's palette and a bin, with renaming hidden behind
/// a tap on the row that nothing announced. Reported from a real phone, and
/// it breaks two rules this repository already wrote down - the assisted
/// controls **around the corners** are the ones older adults are measured not
/// noticing at all, and an icon whose meaning sits far from its function is
/// among the commonest things they get stuck on. A palette is the worst of
/// the three: there is no generation of Korean seniors for whom a painter's
/// palette means colour.
///
/// So the row is **two lines and the controls are words** - 이름, 색깔,
/// 지우기 - each a third of the width and 54px tall. The same argument that
/// replaced the `←` in the corner with 첫 화면으로 가기, one screen along.
///
/// **색깔 carries the button's own colour rather than a glyph**, so there is
/// nothing to learn: the green row's button is green. 지우기 is the one that
/// cannot be undone, so it is lettered in the SOS red and sits at the far
/// end, away from the hand coming off 이름.
///
/// **The handle keeps its symbol and gains the word 순서.**
/// `ReorderableListView` on Android starts a drag on a *long press* and draws
/// nothing at all to say so, which left 드래그 순서 변경 - a thing
/// `04_SCREEN_SPEC` asks for - with no way to discover it;
/// `ReorderableDragStartListener` drags immediately instead, which is the
/// difference between a control and a trick. What it never had was a name.
class _AppRow extends StatelessWidget {
  const _AppRow({
    super.key,
    required this.index,
    required this.app,
    required this.onRename,
    required this.onRecolour,
    required this.onDelete,
  });

  final int index;
  final LauncherApp app;
  final VoidCallback onRename;
  final VoidCallback onRecolour;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: app.baseColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                // Measured, not assumed white — the yellows cannot hold it.
                // The home screen's tiles follow the same rule.
                child: Icon(
                  app.category.icon,
                  color: app.letteringColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  app.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.seniorOnSurface,
                  ),
                ),
              ),
              ReorderableDragStartListener(
                key: AppSettingsKeys.dragHandle(app.id),
                index: index,
                child: const Padding(
                  // A target an ageing hand can land on, rather than the
                  // icon's own bounds.
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.drag_handle,
                        size: 28,
                        color: AppColors.seniorInkMuted,
                      ),
                      Text(
                        '순서',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.seniorInkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _WordButton(
                  buttonKey: AppSettingsKeys.rename(app.id),
                  label: '이름',
                  onTap: onRename,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _WordButton(
                  buttonKey: AppSettingsKeys.colour(app.id),
                  label: '색깔',
                  onTap: onRecolour,
                  // The button's own colour, so there is no symbol to learn.
                  swatch: app.baseColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _WordButton(
                  buttonKey: AppSettingsKeys.delete(app.id),
                  label: '지우기',
                  onTap: onDelete,
                  ink: AppColors.seniorSos,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One of the three words under a button's name.
///
/// Outlined rather than filled: three solid blocks under every row would be
/// louder than the buttons they are about, and this screen is a list of the
/// senior's own home screen.
class _WordButton extends StatelessWidget {
  const _WordButton({
    required this.buttonKey,
    required this.label,
    required this.onTap,
    this.swatch,
    this.ink = AppColors.seniorOnSurface,
  });

  final Key buttonKey;
  final String label;
  final VoidCallback onTap;

  /// Drawn as a filled circle before the word, for 색깔.
  final Color? swatch;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: OutlinedButton(
        key: buttonKey,
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          side: const BorderSide(color: AppColors.seniorHairline, width: 1.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (swatch case final colour?) ...[
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: colour,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.seniorHairline,
                      width: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 버튼 추가하기, as the last row of the list.
///
/// Hollow, like the 추가하기 slot on 자세한 화면 — they are two ways to the
/// same act and were drawn as two different things. Keeping the filled
/// terracotta for the way *out* also stops the two biggest buttons on the
/// screen from being the same colour.
class _AddRow extends StatelessWidget {
  const _AddRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: GestureDetector(
        key: AppSettingsKeys.add,
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.seniorSlotFill,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppColors.seniorSlotBorder,
              width: 2.5,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 30, color: AppColors.seniorSlotInk),
                SizedBox(width: 10),
                Text(
                  '버튼 추가하기',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.seniorSlotInk,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The heading over the three that are not apps.
class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: AppColors.seniorInkMuted,
      ),
    ),
  );
}

/// One of 가족, 소리, 인터넷.
///
/// The same two edits as an app button and neither of the other two: there is
/// exactly one of each, so nothing here is dragged into a different order or
/// deleted. A senior who could delete 가족 would lose the only way to their
/// family from the home screen, and nothing on that screen would say why.
class _FixedRow extends StatelessWidget {
  const _FixedRow({
    required this.app,
    required this.onRename,
    required this.onRecolour,
  });

  final LauncherApp app;
  final VoidCallback onRename;
  final VoidCallback onRecolour;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onRename,
          borderRadius: BorderRadius.circular(20),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: app.baseColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  app.category.icon,
                  color: app.letteringColor,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  app.label,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: AppColors.seniorInk,
                  ),
                ),
              ),
              // The same word the app rows carry, for the same reason: a
              // painter's palette is not a colour to anybody reading this
              // screen. There is no 지우기 and no 순서 here - there is one of
              // each of these and the senior did not put it there.
              SizedBox(
                width: 108,
                child: _WordButton(
                  buttonKey: AppSettingsKeys.colour(app.id),
                  label: '색깔',
                  onTap: onRecolour,
                  swatch: app.baseColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
