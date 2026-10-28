import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

/// What a person button needs: who, and what number.
typedef ContactDraft = ({String name, String number});

/// Keys the tests drive.
class ContactDialogKeys {
  ContactDialogKeys._();

  static const sheet = Key('contact-dialog');
  static const name = Key('contact-dialog-name');
  static const number = Key('contact-dialog-number');
  static const save = Key('contact-dialog-save');
  static const preview = Key('contact-dialog-preview');
}

/// Asks for a person's name and number, on either half of the app.
///
/// The number is typed by the **guardian**, not read from the parent's
/// address book — that is what keeps a contacts permission off the senior's
/// phone. It also means nobody on the parent's end can check it: a mistyped
/// digit sends an elderly person to a stranger, and they have no way to tell.
/// So the dialog shows the number back, formatted, before it will save.
Future<ContactDraft?> askForContact(
  BuildContext context, {
  String title = '사람 추가하기',
  String initialName = '',
  String initialNumber = '',
}) => showDialog<ContactDraft>(
  context: context,
  builder: (context) => _ContactDialog(
    title: title,
    initialName: initialName,
    initialNumber: initialNumber,
  ),
);

/// Groups a Korean mobile or landline number for reading aloud.
///
/// Only for the confirmation line — what is stored and dialled stays digits.
/// A number a guardian cannot read back is a number they cannot check, and
/// checking it is the whole point of showing it.
String formatKoreanNumber(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 9) return digits;
  if (digits.startsWith('02')) {
    final rest = digits.substring(2);
    final head = rest.length >= 8 ? 4 : 3;
    return '02-${rest.substring(0, head)}-${rest.substring(head)}';
  }
  final head = digits.startsWith('1') ? 4 : 3;
  final rest = digits.substring(head);
  final mid = rest.length >= 8 ? 4 : rest.length - 4;
  if (mid <= 0) return digits;
  return '${digits.substring(0, head)}-${rest.substring(0, mid)}'
      '-${rest.substring(mid)}';
}

class _ContactDialog extends StatefulWidget {
  const _ContactDialog({
    required this.title,
    required this.initialName,
    required this.initialNumber,
  });

  final String title;
  final String initialName;
  final String initialNumber;

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _number = TextEditingController(
    text: widget.initialNumber,
  );

  @override
  void initState() {
    super.initState();
    _number.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    super.dispose();
  }

  String get _digits => _number.text.replaceAll(RegExp(r'\D'), '');

  /// Nine digits is the shortest real Korean number (02 landlines). Shorter
  /// than that is a half-typed one, and saving it would put a button on
  /// someone's mother's home screen that dials nothing.
  bool get _ready => _name.text.trim().isNotEmpty && _digits.length >= 9;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: ContactDialogKeys.sheet,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: ContactDialogKeys.name,
            controller: _name,
            autofocus: true,
            style: const TextStyle(fontSize: 22),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: '이름',
              hintText: '딸 영희',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: ContactDialogKeys.number,
            controller: _number,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9\-+ ]')),
            ],
            style: const TextStyle(fontSize: 22),
            decoration: const InputDecoration(
              labelText: '전화번호',
              hintText: '010-1234-5678',
            ),
          ),
          const SizedBox(height: 16),
          // Read back before it can be saved. The parent cannot check this
          // number and will not know a wrong one until a stranger answers.
          Text(
            key: ContactDialogKeys.preview,
            _ready
                ? '${_name.text.trim()} 버튼을 누르면\n'
                      '${formatKoreanNumber(_digits)} 로 전화합니다.'
                : '이름과 전화번호를 모두 넣어 주세요.',
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w700,
              color: _ready ? AppColors.seniorInk : AppColors.seniorInkMuted,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('그만두기', style: TextStyle(fontSize: 18)),
        ),
        TextButton(
          key: ContactDialogKeys.save,
          // Disabled rather than validating on press: the line above already
          // says what is missing, and a button that explains itself only
          // after being pressed is a button that was never going to work.
          onPressed: _ready
              ? () => Navigator.pop(context, (
                  name: _name.text.trim(),
                  number: _digits,
                ))
              : null,
          child: const Text('저장', style: TextStyle(fontSize: 18)),
        ),
      ],
    );
  }
}
