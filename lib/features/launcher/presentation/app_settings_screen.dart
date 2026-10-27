import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/app_category.dart';
import '../../../domain/launcher_app.dart';
import '../application/senior_settings_controller.dart';
import 'widgets/category_picker.dart';
import 'widgets/contact_dialog.dart';

abstract final class AppSettingsKeys {
  /// The grip that starts a reorder. Named so a test can assert it exists:
  /// the list reorders perfectly well without it and shows nothing, which is
  /// how it shipped.
  static Key dragHandle(String id) => Key('drag-handle-$id');
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
              padding: const EdgeInsets.symmetric(vertical: 8),
              onReorder: controller.reorderApps,
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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.seniorPrimary,
                    minimumSize: const Size.fromHeight(64),
                  ),
                  onPressed: () => _add(context, ref),
                  icon: const Icon(Icons.add, size: 28),
                  label: const Text(
                    '버튼 추가하기',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
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

    final name = await _askForName(context, title: '이름 바꾸기', initial: app.label);
    if (name == null) return;
    await ref
        .read(seniorSettingsControllerProvider.notifier)
        .renameApp(app.id, name);
  }

  /// The kind comes first, then the name.
  ///
  /// Both ways in used to add every button as `AppCategory.message`, so a
  /// button called 딸 wore the 문자 icon, came out blue and opened the
  /// messaging app. The kind decides all three, so it has to be asked.
  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final category = await askForCategory(context);
    if (category == null || !context.mounted) return;

    // A person needs a number as well as a name, and there is no sensible
    // default for either.
    if (category.isContact) {
      final draft = await askForContact(context);
      if (draft == null) return;
      await ref
          .read(seniorSettingsControllerProvider.notifier)
          .addApp(
            label: draft.name,
            category: category,
            phoneNumber: draft.number,
          );
      return;
    }

    final name = await _askForName(
      context,
      title: '버튼 추가하기',
      initial: category.defaultLabel,
    );
    if (name == null) return;
    await ref
        .read(seniorSettingsControllerProvider.notifier)
        .addApp(label: name, category: category);
  }

  Future<void> _recolour(
    BuildContext context,
    WidgetRef ref,
    LauncherApp app,
  ) async {
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
                          color: app.color == colour
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
  Future<String?> _askForName(
    BuildContext context, {
    required String title,
    required String initial,
  }) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(title: title, initial: initial),
    );
    return (name == null || name.isEmpty) ? null : name;
  }
}

/// Owns its own controller so it is disposed with the dialog rather than the
/// moment `showDialog` returns — tearing the controller down while the field
/// still holds focus trips a framework assertion.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _field = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _field,
        autofocus: true,
        style: const TextStyle(fontSize: 24),
        decoration: const InputDecoration(hintText: '이름'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('그만두기', style: TextStyle(fontSize: 20)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _field.text.trim()),
          child: const Text('저장', style: TextStyle(fontSize: 20)),
        ),
      ],
    );
  }
}

/// One button in the list.
///
/// **The handle is the whole point of the row.** `ReorderableListView` on
/// Android starts a drag on a *long press* and draws nothing at all to say
/// so, which left 드래그 순서 변경 — a thing `04_SCREEN_SPEC` asks for — with
/// no way to discover it. Long-press is the gesture this app's readers are
/// least likely to know, so an invisible one is the same as a missing
/// feature; on a real phone it was reported as one.
///
/// `ReorderableDragStartListener` also makes the handle drag *immediately*
/// rather than after a hold, which is the difference between a control and a
/// trick.
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: app.baseColor,
          borderRadius: BorderRadius.circular(16),
        ),
        // Measured, not assumed white — the yellows cannot hold it. The
        // home screen's tiles follow the same rule.
        child: Icon(app.category.icon, color: app.letteringColor, size: 28),
      ),
      title: Text(
        app.label,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.seniorOnSurface,
        ),
      ),
      onTap: onRename,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ReorderableDragStartListener(
            key: AppSettingsKeys.dragHandle(app.id),
            index: index,
            child: const Padding(
              // A target an ageing hand can land on, rather than the icon's
              // own bounds.
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              child: Icon(
                Icons.drag_handle,
                size: 30,
                color: AppColors.seniorInkMuted,
              ),
            ),
          ),
          IconButton(
            key: Key('colour-${app.id}'),
            onPressed: onRecolour,
            icon: const Icon(Icons.palette_outlined, size: 28),
            tooltip: '색 바꾸기',
          ),
          IconButton(
            key: Key('delete-${app.id}'),
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 28),
            tooltip: '지우기',
          ),
        ],
      ),
    );
  }
}
