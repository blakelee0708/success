import 'app_category.dart';
import 'senior_settings.dart';

/// Whether the senior has agreed to the paid 안심 케어 features.
///
/// Present from Phase 4 because the column is, but nothing reads it until
/// Phase 6 — `06_PERMISSION_AND_POLICY` makes consent a separate step after
/// payment, so it cannot be inferred from a subscription row later.
enum PaidConsentStatus { none, pending, granted, refused }

/// The parent, as the server knows them.
///
/// Deliberately not the same object as [SeniorSettings]: the settings are what
/// this phone draws right now and must survive with no network, while the
/// profile is the record that outlives the phone. They overlap on screen mode
/// and font size, and [SeniorProfile.applyTo] is the only place that overlap is
/// resolved.
class SeniorProfile {
  const SeniorProfile({
    required this.id,
    required this.displayName,
    required this.customerCode,
    this.ageBand,
    this.screenMode,
    this.fontSize,
    this.paidConsentStatus = PaidConsentStatus.none,
    this.pendingPrimaryGuardianId,
    this.guardianHomeEdits = 0,
    this.removedSlots = const {},
  });

  final String id;
  final String displayName;

  /// What the guardian reads to their parent so the phone can find this
  /// profile. Phase 5 adds the shorter 4-digit code and the invite link.
  final String customerCode;

  final String? ageBand;

  /// Both null until someone has actually chosen. A guardian who creates the
  /// profile before the parent's phone connects has no opinion about either,
  /// and a default here would let that silence overwrite a senior who had
  /// already set 아주 크게.
  final ScreenMode? screenMode;
  final FontSize? fontSize;

  final PaidConsentStatus paidConsentStatus;

  /// A guardian waiting for the senior to agree that they should be the one
  /// answering for them. Null when nothing is outstanding — only one request
  /// can be open at a time, so asking is never two questions at once.
  final String? pendingPrimaryGuardianId;

  /// How many times a guardian has saved this parent's home screen from
  /// their own phone.
  ///
  /// The senior's own saves are never counted - their phone edits its own
  /// buttons without limit, and that is the rule the whole pricing line
  /// rests on. The free allowance is lifetime rather than monthly, so this
  /// only ever goes up; `replace_home_apps` is where it is enforced and this
  /// is what lets the screen say the number *before* a save is refused.
  final int guardianHomeEdits;

  /// Which of 가족, 소리, 인터넷 and 긴급 구조 요청 the family has taken off
  /// the home screen.
  ///
  /// On the profile rather than in `home_apps` because what is recorded is
  /// the *absence* of a button, and that table holds rows. Absence there has
  /// always meant *nobody has edited this one yet, draw the default*.
  final Set<AppCategory> removedSlots;

  /// Folds the server's copy into what this phone already has.
  ///
  /// The button list is not touched here — it syncs through `home_apps`, and
  /// merging two lists of buttons is a different problem from picking one of
  /// two enum values.
  SeniorSettings applyTo(SeniorSettings settings) => settings.copyWith(
    screenMode: screenMode ?? settings.screenMode,
    fontSize: fontSize ?? settings.fontSize,
    // Taken as the server's, not merged. A guardian removing 긴급 구조 요청
    // for their mother has to reach her phone, and a union of the two sides
    // would make putting one back impossible from the other phone.
    removedSlots: removedSlots,
  );

  /// Added because the in-memory twin rebuilt this by hand in two places and
  /// **both dropped `pendingPrimaryGuardianId`** - a field that decides
  /// whether the senior's home screen raises the handover card. Every new
  /// field would have been dropped the same way, silently, in a double that
  /// exists to make tests trustworthy.
  SeniorProfile copyWith({
    String? displayName,
    ScreenMode? screenMode,
    FontSize? fontSize,
    PaidConsentStatus? paidConsentStatus,
    int? guardianHomeEdits,
    Set<AppCategory>? removedSlots,
  }) => SeniorProfile(
    id: id,
    displayName: displayName ?? this.displayName,
    customerCode: customerCode,
    ageBand: ageBand,
    screenMode: screenMode ?? this.screenMode,
    fontSize: fontSize ?? this.fontSize,
    paidConsentStatus: paidConsentStatus ?? this.paidConsentStatus,
    pendingPrimaryGuardianId: pendingPrimaryGuardianId,
    guardianHomeEdits: guardianHomeEdits ?? this.guardianHomeEdits,
    removedSlots: removedSlots ?? this.removedSlots,
  );

  static SeniorProfile? fromRow(Map<String, Object?> row) {
    final id = row['id'];
    final displayName = row['display_name'];
    final customerCode = row['customer_code'];
    if (id is! String || displayName is! String || customerCode is! String) {
      return null;
    }
    return SeniorProfile(
      id: id,
      displayName: displayName,
      customerCode: customerCode,
      ageBand: row['age_band'] as String?,
      screenMode: _byName(ScreenMode.values, row['screen_mode']),
      fontSize: _byName(FontSize.values, row['font_size']),
      paidConsentStatus:
          _byName(PaidConsentStatus.values, row['paid_consent_status']) ??
          PaidConsentStatus.none,
      pendingPrimaryGuardianId: row['pending_primary_guardian_id'] as String?,
      guardianHomeEdits: switch (row['guardian_home_edits']) {
        final int n => n,
        final num n => n.toInt(),
        _ => 0,
      },
      // A name this version does not know is ignored rather than rejected: a
      // newer phone in the family must not stop an older one syncing at all.
      removedSlots: switch (row['removed_slots']) {
        final List names => {
          for (final name in names) ?_byName(AppCategory.values, name),
        },
        _ => const <AppCategory>{},
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SeniorProfile &&
      other.id == id &&
      other.displayName == displayName &&
      other.customerCode == customerCode &&
      other.ageBand == ageBand &&
      other.screenMode == screenMode &&
      other.fontSize == fontSize &&
      other.paidConsentStatus == paidConsentStatus &&
      other.pendingPrimaryGuardianId == pendingPrimaryGuardianId &&
      other.guardianHomeEdits == guardianHomeEdits;

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    customerCode,
    ageBand,
    screenMode,
    fontSize,
    paidConsentStatus,
    pendingPrimaryGuardianId,
    guardianHomeEdits,
  );
}

T? _byName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
