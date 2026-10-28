import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../presentation/widgets/manual_sketches.dart';

/// 사용법 — the seven things a senior actually gets stuck on.
///
/// **Not a tour.** A manual read front to back is abandoned at the third
/// page; somebody who is stuck is stuck on exactly one thing, and the list is
/// what lets them press that one. Nothing here is numbered as a step of
/// anything larger.
///
/// What is left out is as deliberate as what is in. `버튼을 누르면 앱이
/// 열려요` is not here: nobody is stuck on that. 긴급 구조 요청 is not here
/// either - a red bar across the bottom is its own explanation.
///
/// **No swiping and no scrolling.** Both are the gestures this app's readers
/// fail at most, so the list fits one screen at every text size and a card is
/// one card with one button.
class ManualTopic {
  const ManualTopic({
    required this.key,
    required this.title,
    required this.lines,
    required this.drawing,
  });

  /// Names the row and the card, for tests.
  final String key;

  /// What the row says, and the card's headline. Short enough to be one line
  /// of the row at every text size.
  final String title;

  /// The card's body. Every entry is a whole line - Korean glyphs are about
  /// as wide as the type size, so these are counted rather than wrapped. An
  /// empty string is a gap.
  final List<String> lines;

  /// A depiction of the real screen, with the numbers the lines refer to.
  final Widget drawing;
}

const _red = AppColors.seniorSos;
const _amber = AppColors.seniorFamily;
const _sand = AppColors.seniorUtility;
const _brown = AppColors.seniorMore;
const _green = AppColors.seniorButtonGreen;

final manualTopics = <ManualTopic>[
  ManualTopic(
    key: 'home',
    title: '첫 화면으로 돌아가기',
    // The one thing seniors get stuck on more than anything else: they go
    // somewhere and cannot get out. It is first for that reason.
    lines: const [
      '어느 화면에서든',
      '맨 아래 빨간 버튼을',
      '누르시면 됩니다.',
      '',
      '홈 버튼을 눌러도 됩니다.',
    ],
    drawing: const ManualFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ManualPill(label: '설정', face: _brown, height: 30),
          SizedBox(height: 6),
          ManualPill(label: '글씨 크기 조절하기', face: _green, height: 30),
          SizedBox(height: 14),
          Center(child: ManualArrow()),
          SizedBox(height: 6),
          ManualPill(
            label: '첫 화면으로 가기',
            face: AppColors.seniorPrimary,
            step: 1,
            height: 46,
          ),
        ],
      ),
    ),
  ),
  ManualTopic(
    key: 'font',
    title: '글씨 크게 하기',
    lines: const [
      '설정에서',
      '글씨 크기 조절하기를',
      '누르세요.',
      '',
      '네 가지 중에 고르시면',
      '바로 커집니다.',
    ],
    drawing: const ManualFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ManualPill(label: '앱 설정하기', face: AppColors.seniorButtonPurple, height: 34),
          SizedBox(height: 8),
          ManualPill(
            label: '글씨 크기 조절하기',
            face: _green,
            step: 1,
            height: 38,
          ),
        ],
      ),
    ),
  ),
  ManualTopic(
    key: 'rename',
    title: '버튼 이름과 색 바꾸기',
    lines: const [
      '설정에서',
      '앱 설정하기를 누르세요.',
      '',
      '버튼마다 이름과 색깔이',
      '있어요. 누르면 바뀝니다.',
    ],
    // `바꾸시면 바로 바뀌어요` is not repeated here. It is already written
    // under 앱 설정's own exit button, which is where somebody reads it at
    // the moment it matters - and at 제일 크게 this card ran 58px past its
    // box with it.
    drawing: const ManualFrame(
      child: ManualSettingRow(
        label: '전화',
        face: _green,
        nameStep: 1,
        colourStep: 2,
      ),
    ),
  ),
  ManualTopic(
    key: 'add',
    title: '버튼 더하기, 지우기',
    // Cut to fit 제일 크게, where the first draft ran 113px past the card.
    // The floor stayed and the preamble went: 같은 화면에서 합니다 is
    // something the drawing already shows.
    lines: const [
      '버튼마다 지우기가 있어요.',
      '맨 아래는 버튼 추가하기.',
      '',
      '버튼은 네 개까지만',
      '줄일 수 있어요.',
    ],
    drawing: const ManualFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ManualSettingRow(label: '전화', face: _green, deleteStep: 1),
          SizedBox(height: 12),
          ManualPill(
            label: '＋ 버튼 추가하기',
            face: Colors.transparent,
            hollow: true,
            step: 2,
            height: 40,
          ),
        ],
      ),
    ),
  ),
  ManualTopic(
    key: 'family',
    title: '가족에게 연락하기',
    // Seniors fail at finding *people* far more than at finding apps - 연락처
    // and scrolling is where they give up. This button is the whole answer.
    lines: const [
      '첫 화면의 노란 가족 버튼을',
      '누르세요.',
      '',
      '자녀분과 주고받은 이야기가',
      '나옵니다.',
    ],
    drawing: const ManualFrame(
      child: Row(
        children: [
          Expanded(
            child: ManualPill(
              label: '가족',
              face: _amber,
              ink: AppColors.seniorInk,
              icon: Icons.family_restroom,
              step: 1,
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: ManualPill(label: '더 보기', face: _brown, icon: Icons.apps),
          ),
        ],
      ),
    ),
  ),
  ManualTopic(
    key: 'sound',
    title: '전화벨이 안 울릴 때',
    // 엄마가 전화를 안 받아 is why the family installs this app, and a phone
    // left on vibrate is the first cause of it.
    lines: const [
      '첫 화면 위쪽의',
      '소리 버튼을 누르세요.',
      '',
      '누를 때마다 소리와 진동이',
      '바뀝니다.',
    ],
    drawing: const ManualFrame(
      child: Row(
        children: [
          Expanded(
            child: ManualPill(
              label: '소리 켜짐',
              face: _sand,
              ink: AppColors.seniorInk,
              icon: Icons.volume_up_rounded,
              step: 1,
              height: 36,
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: ManualPill(
              label: '인터넷',
              face: _sand,
              ink: AppColors.seniorInk,
              icon: Icons.wifi_rounded,
              height: 36,
            ),
          ),
        ],
      ),
    ),
  ),
  ManualTopic(
    key: 'support',
    title: '잘 안 될 때',
    // The one route that needs nobody. Every other way out of 설정 assumes a
    // child at the other end.
    lines: const [
      '설정에서',
      '문의하기를 누르세요.',
      '',
      '번호가 나옵니다.',
      '고객센터에 그 번호를',
      '불러주세요.',
    ],
    drawing: const ManualFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ManualPill(label: '문의하기', face: _green, icon: Icons.support_agent_rounded, step: 1, height: 38),
          SizedBox(height: 12),
          Center(child: ManualArrow()),
          SizedBox(height: 8),
          ManualPill(label: '482 913', face: _red, height: 42),
        ],
      ),
    ),
  ),
];
