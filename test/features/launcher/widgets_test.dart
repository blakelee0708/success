import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/domain/app_category.dart';
import 'package:app/domain/launcher_app.dart';
import 'package:app/features/launcher/presentation/widgets/app_tile.dart';
import 'package:app/features/launcher/presentation/widgets/sos_button.dart';

void main() {
  testWidgets('AppTile shows label and icon, fires onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTile(
            app: const LauncherApp(
              id: 'phone',
              label: '전화',
              category: AppCategory.phone,
            ),
            onTap: () => tapped = true,
          ),
        ),
      ),
    );
    expect(find.text('전화'), findsOneWidget);
    expect(find.byIcon(Icons.call), findsOneWidget);
    await tester.tap(find.byType(AppTile));
    expect(tapped, isTrue);
  });

  testWidgets('SosButton shows SOS label and fires onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SosButton(onTap: () => tapped = true)),
      ),
    );
    expect(find.text('긴급 구조 요청'), findsOneWidget);
    await tester.tap(find.byType(SosButton));
    expect(tapped, isTrue);
  });
}
