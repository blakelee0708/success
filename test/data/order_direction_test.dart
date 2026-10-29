import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **`ascending` defaults to `false` in postgrest-dart.**
///
/// `PostgrestTransformBuilder.order` is declared `order(String column,
/// {bool ascending = false, ...})` and serialises `'$column.desc'`, which is
/// the opposite of supabase-js and the opposite of what anybody writing
/// `.order('created_at')` means. Three calls in this repository were written
/// that way and one of them was a bug on a real phone: the conversation came
/// back newest first, `ConversationView` draws index 0 at the bottom, and the
/// thread read backwards. The other two were saved by a client-side sort that
/// happened to exist.
///
/// **No test using the in-memory twins could have caught it**, for the same
/// reason none caught the missing anonymous sign-in: the twins return
/// whatever order they stored, and only a live project sorts. So the guard is
/// on the source instead, exactly as `application_id_test` reads
/// `build.gradle.kts` off disk.
void main() {
  test('every .order() names its direction', () {
    final offenders = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        // Prose about `.order(` is not a call. The note in
        // `message_repository.dart` quotes the mistake it is warning about.
        if (line.startsWith('//') || line.startsWith('*')) continue;
        if (!lines[i].contains('.order(')) continue;
        // The argument list may wrap, so read to the closing bracket.
        final buffer = StringBuffer();
        var depth = 0;
        for (var j = i; j < lines.length && j < i + 6; j++) {
          buffer.write(lines[j]);
          depth += '('.allMatches(lines[j]).length;
          depth -= ')'.allMatches(lines[j]).length;
          if (depth <= 0) break;
        }
        if (!buffer.toString().contains('ascending:')) {
          offenders.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'postgrest-dart defaults to descending, so a bare .order() is '
          'almost never what was meant. Write ascending: true or '
          'ascending: false and say why.',
    );
  });
}
