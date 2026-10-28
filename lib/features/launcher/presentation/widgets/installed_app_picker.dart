import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/app_launcher.dart';

class InstalledAppPickerKeys {
  InstalledAppPickerKeys._();

  static const sheet = Key('installed-app-picker');
  static const empty = Key('installed-app-picker-empty');
  static const loading = Key('installed-app-picker-loading');

  static Key option(String packageName) => Key('installed-app-$packageName');
}

/// Picks one of the apps already on this phone.
///
/// This is the half of 사람 버튼's argument that was missing. Seniors do not
/// fail at *opening* apps — they fail at **finding** them, and the app they
/// most want is usually their 고스톱 or their bank, which is not one of six
/// categories and never will be.
///
/// Full screen rather than a dialog: a phone has sixty to a hundred of these
/// and a box in the middle of the screen would show four at a time.
///
/// **It waits on the channel, and that is allowed here** — the rule is that
/// nothing a *senior is looking at on the home screen* may wait on the
/// platform. This is a settings screen they opened on purpose, the wait is
/// one call, and the alternative is a list that fills in while they are
/// already reading it.
Future<InstalledApp?> askForInstalledApp(BuildContext context, WidgetRef ref) =>
    showDialog<InstalledApp>(
      context: context,
      useSafeArea: false,
      builder: (context) => Dialog.fullscreen(
        key: InstalledAppPickerKeys.sheet,
        backgroundColor: AppColors.seniorSurface,
        child: _PickerBody(launcher: ref.read(appLauncherProvider)),
      ),
    );

class _PickerBody extends StatefulWidget {
  const _PickerBody({required this.launcher});

  final AppLauncher launcher;

  @override
  State<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends State<_PickerBody> {
  late final Future<List<InstalledApp>> _apps = widget.launcher.installedApps();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back, size: 30),
                  color: AppColors.seniorInk,
                ),
                const Expanded(
                  child: Text(
                    '어떤 앱을 놓을까요?',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: AppColors.seniorInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<InstalledApp>>(
              future: _apps,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    key: InstalledAppPickerKeys.loading,
                    child: CircularProgressIndicator(),
                  );
                }
                final apps = snapshot.data!;
                // A phone that answered with nothing is not an error screen.
                // `flutter test` and a desktop build both land here, and so
                // would a phone whose launcher service is wedged.
                if (apps.isEmpty) {
                  return const Center(
                    key: InstalledAppPickerKeys.empty,
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        '이 폰에서 앱 목록을\n읽지 못했어요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          height: 1.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.seniorInkMuted,
                        ),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: apps.length,
                  itemBuilder: (context, i) => _Row(app: apps[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.app});

  final InstalledApp app;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: InstalledAppPickerKeys.option(app.packageName),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      leading: SizedBox(
        width: 56,
        height: 56,
        // Its own icon, because that is what the senior recognises. A grey
        // glyph beside a name they half-remember is two things to decode.
        child: app.icon == null
            ? const Icon(Icons.apps_rounded, size: 40)
            : Image.memory(app.icon!, filterQuality: FilterQuality.medium),
      ),
      title: Text(
        app.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.seniorOnSurface,
        ),
      ),
      onTap: () => Navigator.of(context).pop(app),
    );
  }
}
