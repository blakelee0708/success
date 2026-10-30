import 'package:flutter_test/flutter_test.dart';
import 'package:app/domain/app_category.dart';
import 'package:app/domain/launcher_app.dart';

void main() {
  test('easy defaults are the 2x2 set: 전화 문자 사진 보기 영상 보기', () {
    expect(defaultEasyApps.map((a) => a.label).toList(), [
      '전화',
      '문자',
      '사진 보기',
      '영상 보기',
    ]);
    expect(defaultEasyApps.map((a) => a.category).toList(), [
      AppCategory.phone,
      AppCategory.message,
      AppCategory.gallery,
      AppCategory.youtube,
    ]);
  });

  test('detailed defaults are the 6 set in spec order', () {
    expect(defaultDetailedApps.map((a) => a.label).toList(), [
      '전화',
      '문자',
      '카카오톡',
      '영상 보기',
      '사진찍기',
      '사진 보기',
    ]);
    expect(defaultDetailedApps.length, 6);
  });
}
