import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Widget keys the tests drive.
class GuardianNavKeys {
  GuardianNavKeys._();

  static const bar = Key('guardian-nav');

  static Key destination(String label) => Key('guardian-nav-$label');

  static Key badge(String label) => Key('guardian-nav-badge-$label');
}

/// One destination of [GuardianNavBar].
class GuardianDestination {
  const GuardianDestination({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.badge = 0,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;

  /// Unread things waiting behind this tab, or zero.
  ///
  /// A number rather than a dot, because 1 and 9 are different news to
  /// somebody deciding whether to open it now or after the meeting.
  final int badge;
}

/// The bar across the bottom of the guardian app.
///
/// Hand-drawn rather than a Material [NavigationBar], which brings its own
/// 80px height, its own pill-shaped indicator and its own type scale — three
/// things that have to be fought rather than used once the rest of the screen
/// is on this type scale.
class GuardianNavBar extends StatelessWidget {
  const GuardianNavBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<GuardianDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: GuardianNavKeys.bar,
      decoration: const BoxDecoration(
        color: Color(0xEBFFFFFF),
        border: Border(top: BorderSide(color: AppColors.guardianRule)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: _Destination(
                    destination: destinations[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Destination extends StatelessWidget {
  const _Destination({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final GuardianDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? AppColors.guardianPrimary
        : AppColors.guardianInkDisabled;

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        key: GuardianNavKeys.destination(destination.label),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The badge rides on the icon rather than taking a row of its
            // own: the bar is 60px and the label already scales down to fit.
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  selected ? destination.activeIcon : destination.icon,
                  size: 22,
                  color: color,
                ),
                if (destination.badge > 0)
                  Positioned(
                    top: -5,
                    right: -9,
                    child: Container(
                      key: GuardianNavKeys.badge(destination.label),
                      constraints: const BoxConstraints(minWidth: 17),
                      height: 17,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: AppColors.guardianBadge,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        destination.badge > 99 ? '99+' : '${destination.badge}',
                        style: const TextStyle(
                          fontSize: 10,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            // Scales down rather than wrapping: 홈 화면 is the longest label
            // and it has 78px to live in on a 390px phone.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                destination.label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
