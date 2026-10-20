import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/clay_pad.dart';

/// First screen. A hand holds a phone; the phone's screen is the start button.
///
/// There is no separate 시작하기 CTA — see
/// `docs/superpowers/specs/2026-07-29-splash-and-guardian-entry-design.md`.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.entranceTilt = -42});

  /// The angle the hand swings up from, in degrees, negative to the left.
  ///
  /// A tilt the screen *rests* at does not work with this illustration: the
  /// phone leaves the frame, the 눌러보세요 drawn over it lies on its side,
  /// and a render lit from above ends up lit from the side. As the start of a
  /// movement none of that matters — the hand is only there for a moment on
  /// its way to upright, and coming in from off-frame is the point.
  final double entranceTilt;

  /// How long the hand takes to swing up and settle.
  static const entrance = Duration(milliseconds: 780);

  static const tapTargetKey = Key('splash-tap-target');
  static const guardianCardKey = Key('splash-guardian-card');

  /// How long `준비하고 있어요` shows before the screen-mode choice appears.
  ///
  /// Navigating on the same frame as the tap leaves no sign the tap landed,
  /// and this audience answers that by tapping again.
  static const enteringPause = Duration(milliseconds: 500);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  /// The one-shot swing up. Separate from [_loop], which never ends: a
  /// repeating controller cannot also be the thing that finishes.
  late final AnimationController _raise = AnimationController(
    vsync: this,
    duration: SplashScreen.entrance,
  );

  /// True once the hand has arrived. Until then the phone's screen is dark
  /// and nothing is tappable: the start control is still moving, and asking
  /// a senior to hit a moving target — or worse, inviting a tap and then
  /// ignoring it — is the one thing this screen must not do.
  bool _landed = false;

  bool _entering = false;

  @override
  void initState() {
    super.initState();
    _raise.forward().whenComplete(() {
      if (mounted) setState(() => _landed = true);
    });
  }

  @override
  void dispose() {
    _loop.dispose();
    _raise.dispose();
    super.dispose();
  }

  void _onPhoneTap() {
    if (_entering) return;
    setState(() => _entering = true);
    Future<void>.delayed(SplashScreen.enteringPause, () {
      if (mounted) context.go(Routes.seniorOnboarding);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          // White, like every other senior screen since the 2026-10-20
          // review. The illustration is a PNG with a transparent background,
          // so the cream it used to sit on was painted here and nowhere else.
          color: AppColors.seniorBackground,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _AmbientWashes(),
            _Illustration(
              entering: _entering,
              loop: _loop,
              raise: _raise,
              landed: _landed,
              onTap: _onPhoneTap,
              startTilt: widget.entranceTilt,
            ),
            const _BottomScrim(),
            const _Wordmark(),
            const _GuardianCard(),
          ],
        ),
      ),
    );
  }
}

/// Two radial glows, barely there. On the cream ground they kept it from
/// looking like paper; on white they are what stopped it being white, so they
/// are turned down to the faintest warmth rather than removed — the
/// illustration is a warm render and a dead-white field behind it looks cut
/// out rather than lit.
class _AmbientWashes extends StatelessWidget {
  const _AmbientWashes();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -170,
            left: -110,
            child: _wash(420, const Color(0xFF9AA0A8), 0.05),
          ),
          Positioned(
            top: 300,
            right: -160,
            child: _wash(340, const Color(0xFF9AA0A8), 0.035),
          ),
        ],
      ),
    );
  }

  Widget _wash(double size, Color color, double opacity) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [
          color.withValues(alpha: opacity),
          color.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.7],
      ),
    ),
  );
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 78,
      left: 0,
      right: 0,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                '잘보이네',
                style: TextStyle(
                  fontSize: 41,
                  height: 1.0,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -2,
                  color: AppColors.splashInk,
                ),
              ),
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(left: 2, bottom: 5),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.splashAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _rule(),
              const SizedBox(width: 9),
              const Text(
                '크게 보고 쉽게 쓰는',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2.4,
                  color: AppColors.splashTagline,
                ),
              ),
              const SizedBox(width: 9),
              _rule(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rule() => Container(
    width: 26,
    height: 1,
    color: AppColors.splashInk.withValues(alpha: 0.28),
  );
}

/// The hand illustration, anchored so the phone lands in the middle of the
/// screen, with the tap target sitting over the phone's blank display.
class _Illustration extends StatelessWidget {
  const _Illustration({
    required this.entering,
    required this.loop,
    required this.raise,
    required this.landed,
    required this.onTap,
    this.startTilt = -42,
  });

  final bool entering;
  final Animation<double> loop;
  final VoidCallback onTap;

  /// Drives the swing up. Runs once, then the hand is upright for good.
  final Animation<double> raise;

  /// Whether the swing has finished. Nothing on the phone is shown or
  /// tappable before it has.
  final bool landed;

  /// The angle it swings up from, negative to the left.
  final double startTilt;

  // The design draws the illustration in a 390x801 box sitting 76px above the
  // bottom edge; the tap target is a fraction of that box.
  static const _designWidth = 390.0;
  static const _designHeight = 801.0;
  static const _bottomGap = 76.0;
  static const _tapLeft = 0.202;
  static const _tapTop = 0.294;
  static const _tapWidth = 0.576;
  static const _tapHeight = 0.54;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fit the box to the width, but never let it grow so tall that the
        // phone climbs off the top of a short screen.
        final available = constraints.maxHeight - _bottomGap;
        var boxWidth = constraints.maxWidth;
        var boxHeight = boxWidth * _designHeight / _designWidth;
        if (boxHeight > available) {
          boxHeight = available;
          boxWidth = boxHeight * _designWidth / _designHeight;
        }

        return Stack(
          children: [
            Positioned(
              left: (constraints.maxWidth - boxWidth) / 2,
              bottom: _bottomGap,
              width: boxWidth,
              height: boxHeight,
              // The phone's screen is drawn by Flutter on top of the photo,
              // so the swing has to turn both together or the two come apart.
              //
              // `easeOutBack` overshoots a little past upright and settles
              // back, which is the 딱 at the end of the movement. Pivoting at
              // the wrist rather than the middle of the box is what makes it
              // read as a hand being raised instead of a picture spinning.
              child: AnimatedBuilder(
                animation: raise,
                builder: (context, child) {
                  final t = Curves.easeOutBack.transform(raise.value);
                  return Transform.translate(
                    offset: Offset(0, (1 - raise.value) * boxHeight * 0.16),
                    child: Transform.rotate(
                      angle: startTilt * (1 - t) * math.pi / 180,
                      alignment: const Alignment(-0.45, 1),
                      child: child,
                    ),
                  );
                },
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.asset(
                        'assets/images/hand_phone.png',
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomCenter,
                      ),
                    ),
                    Positioned(
                      left: boxWidth * _tapLeft,
                      top: boxHeight * _tapTop,
                      width: boxWidth * _tapWidth,
                      height: boxHeight * _tapHeight,
                      child: GestureDetector(
                        key: SplashScreen.tapTargetKey,
                        behavior: HitTestBehavior.opaque,
                        onTap: landed ? onTap : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Center(
                            // The screen lights up as the phone arrives.
                            child: AnimatedOpacity(
                              opacity: landed ? 1 : 0,
                              duration: const Duration(milliseconds: 240),
                              child: entering
                                  ? _EnteringState(loop: loop)
                                  : _IdleState(loop: loop),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Resting state: a pulsing tap circle with two rings expanding out of it.
class _IdleState extends StatelessWidget {
  const _IdleState({required this.loop});

  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 132,
          height: 132,
          child: AnimatedBuilder(
            animation: loop,
            builder: (context, _) => Stack(
              alignment: Alignment.center,
              children: [
                _ring(loop.value),
                _ring((loop.value + 0.5) % 1.0),
                Transform.scale(
                  scale: 1 + 0.06 * _pulse(loop.value),
                  child: Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.splashAccent,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.splashAccent.withValues(alpha: 0.34),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.touch_app_outlined,
                      size: 60,
                      color: Color(0xFFFFF6EE),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          '눌러보세요',
          style: TextStyle(
            fontSize: 38,
            height: 1.1,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.6,
            color: AppColors.splashAccent,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          '스마트폰이\n쉬워져요',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            height: 1.4,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            color: AppColors.splashPromptInk,
          ),
        ),
      ],
    );
  }

  /// Rings grow from 0.72 to 1.5 while fading out, then restart.
  Widget _ring(double t) {
    final grown = t / 0.7;
    if (grown > 1) return const SizedBox.shrink();
    return Transform.scale(
      scale: 0.72 + (1.5 - 0.72) * grown,
      child: Container(
        width: 132,
        height: 132,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.splashAccent.withValues(alpha: 0.55 * (1 - grown)),
            width: 3,
          ),
        ),
      ),
    );
  }

  /// 0 → 1 → 0 over one loop, so the circle breathes rather than jumps.
  double _pulse(double t) => t < 0.5 ? t * 2 : (1 - t) * 2;
}

/// Shown for [SplashScreen.enteringPause] after the tap, so the tap is felt.
class _EnteringState extends StatelessWidget {
  const _EnteringState({required this.loop});

  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: loop,
          builder: (context, _) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) => _dot(i)),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          '준비하고 있어요\n잠시만 기다려 주세요',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            height: 1.5,
            fontWeight: FontWeight.w700,
            color: AppColors.splashPromptInk,
          ),
        ),
      ],
    );
  }

  Widget _dot(int index) {
    final t = (loop.value - index * 0.18) % 1.0;
    final lit = t < 0.4 ? t / 0.4 : 0.0;
    return Container(
      width: 9,
      height: 9,
      margin: const EdgeInsets.symmetric(horizontal: 3.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.splashAccent.withValues(alpha: 0.25 + 0.75 * lit),
      ),
    );
  }
}

/// Fades the illustration out toward the bottom so the card stays readable.
class _BottomScrim extends StatelessWidget {
  const _BottomScrim();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 250,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                AppColors.seniorBackground,
                AppColors.seniorBackground.withValues(alpha: 0.85),
                AppColors.seniorBackground.withValues(alpha: 0),
              ],
              stops: const [0.34, 0.62, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

class _GuardianCard extends StatelessWidget {
  const _GuardianCard();

  /// White, lettered in terracotta. A colour of its own was tried four ways
  /// and each one pulled the eye to a control the senior is not meant to use:
  /// this card is for the son or daughter standing next to them.
  static const _ink = AppColors.seniorPrimary;

  @override
  Widget build(BuildContext context) {
    final label = _ink.withValues(alpha: 0.62);
    return Positioned(
      left: 20,
      right: 20,
      bottom: 34,
      child: GestureDetector(
        key: SplashScreen.guardianCardKey,
        behavior: HitTestBehavior.opaque,
        onTap: () => context.go(Routes.guardianStart),
        child: ClayPad(
          light: Color(0xFFFFFFFF),
          face: Color(0xFFFFFFFF),
          deep: Color(0xFFF5F6F7),
          wall: Color(0xFFDCDEE1),
          radius: 22,
          wallHeight: 6,
          sheen: 0.4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _ink.withValues(alpha: 0.35),
                      width: 1.3,
                    ),
                  ),
                  child: Icon(Icons.people_outline, size: 22, color: _ink),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '가족 및 보호자분들은',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: label,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '여기를 눌러주세요',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: _ink,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: label),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
