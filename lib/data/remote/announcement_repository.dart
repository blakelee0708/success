import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Who a 공지 is for.
enum AnnouncementAudience { senior, guardian }

/// A service notice written on the server: 점검, 기능 안내, 업데이트 안내.
///
/// **It reaches phones that will never be updated**, which is the reason it
/// exists at all. A launcher is the app Play will not update, so a notice
/// built into a later version cannot reach the phones still on this one.
class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    this.belowBuild,
  });

  final String id;
  final String title;
  final String body;

  /// Shown only to builds lower than this. Null shows it to everybody.
  final int? belowBuild;

  bool showsTo(int? build) =>
      belowBuild == null || (build != null && build < belowBuild!);

  static Announcement? fromRow(Map<String, Object?> row) {
    final id = row['id'];
    final title = row['title'];
    final body = row['body'];
    if (id is! String || title is! String || body is! String) return null;
    return Announcement(
      id: id,
      title: title.trim(),
      body: body.trim(),
      belowBuild: (row['below_build'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Announcement &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      other.belowBuild == belowBuild;

  @override
  int get hashCode => Object.hash(id, title, body, belowBuild);
}

abstract class AnnouncementRepository {
  /// The notices running now for [audience], newest first. Empty on any
  /// failure: a notice that cannot be read is a notice not shown, never an
  /// error on a screen somebody opened for something else.
  Future<List<Announcement>> running(AnnouncementAudience audience);
}

class SupabaseAnnouncementRepository implements AnnouncementRepository {
  SupabaseAnnouncementRepository(this._client);

  final sb.SupabaseClient _client;

  @override
  Future<List<Announcement>> running(AnnouncementAudience audience) async {
    try {
      // The running window is the policy's; only the audience is asked here.
      final rows = await _client
          .from('announcements')
          .select()
          .inFilter('audience', [audience.name, 'both'])
          .order('starts_at', ascending: false)
          .limit(10);
      return [for (final row in rows) ?Announcement.fromRow(row)];
    } on Object {
      return const [];
    }
  }
}

/// Stand-in used when the build carries no Supabase keys, and by tests.
class InMemoryAnnouncementRepository implements AnnouncementRepository {
  InMemoryAnnouncementRepository({
    this.forSenior = const [],
    this.forGuardian = const [],
  });

  List<Announcement> forSenior;
  List<Announcement> forGuardian;

  @override
  Future<List<Announcement>> running(AnnouncementAudience audience) async =>
      switch (audience) {
        AnnouncementAudience.senior => forSenior,
        AnnouncementAudience.guardian => forGuardian,
      };
}

/// What this phone has already been shown and closed.
///
/// **Kept on the phone, never told to the server**: whether somebody read a
/// service notice is nothing the company needs, and a parent's phone is the
/// last place to start collecting it. Unlike 나중에 볼게요 on a family
/// message, closing one of these is final - it was the company talking.
class AnnouncementDismissals {
  static const idsKey = 'dismissed_announcements';
  static const updateKey = 'dismissed_update_build';

  Future<Set<String>> ids() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(idsKey) ?? const []).toSet();
    } on Object {
      return const {};
    }
  }

  Future<void> dismiss(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = {...?prefs.getStringList(idsKey), id};
      await prefs.setStringList(idsKey, ids.toList());
    } on Object {
      // A notice that comes back once more is a smaller cost than a tap
      // that throws.
    }
  }

  /// The newest build the guardian said 나중에 to. A newer one asks again.
  Future<int?> updateDismissedFor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(updateKey);
    } on Object {
      return null;
    }
  }

  Future<void> dismissUpdate(int build) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(updateKey, build);
    } on Object {
      // As above.
    }
  }
}
