import 'package:flutter/material.dart';

/// Asks what to call a button.
///
/// Shared, because two entry points add buttons — 앱 설정하기 and the hollow
/// slot on 자세한 화면 — and a second copy of a dialog is a second place for
/// the wording to drift.
Future<String?> askForButtonName(
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
