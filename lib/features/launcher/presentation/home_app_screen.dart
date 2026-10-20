import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'widgets/default_home_prompt.dart';

/// 첫 화면으로 정하기 — the way back for a senior who answered 나중에 when
/// onboarding asked, and for the phones that refuse the chooser outright.
///
/// A screen of its own rather than a card on the home. On the home it sat
/// over the tiles and could not be dismissed, and at 제일 크게 it asked for
/// more height than the phone had — the tiles shrank to 12px instead of
/// overflowing, because every tile is a `FittedBox`.
class HomeAppScreen extends StatelessWidget {
  const HomeAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.seniorBackground,
      appBar: AppBar(
        backgroundColor: AppColors.seniorBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          '첫 화면으로 정하기',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
            color: AppColors.seniorInk,
          ),
        ),
      ),
      body: const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: SingleChildScrollView(child: DefaultHomePrompt()),
        ),
      ),
    );
  }
}
