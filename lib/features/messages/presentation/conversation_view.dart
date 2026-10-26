import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/remote/message_repository.dart';
import '../../../data/remote/senior_link_repository.dart';
import '../../../domain/family_message.dart';
import '../application/message_controller.dart';
import '../data/speech_reader.dart';

/// Widget keys the tests drive.
class ConversationKeys {
  ConversationKeys._();

  static const list = Key('conversation-list');
  static const field = Key('conversation-field');
  static const send = Key('conversation-send');
  static const quota = Key('conversation-quota');
  static const error = Key('conversation-error');
  static const empty = Key('conversation-empty');

  /// The 읽어드리기 target on one received message, on the parent's phone.
  static Key read(String messageId) => Key('conversation-read-$messageId');
}

/// 가족 메시지, drawn the same way on both phones.
///
/// One widget for both sides on purpose. The conversation is the same
/// conversation, and two implementations of it would drift — the guardian's
/// copy gaining a feature the parent's never got.
///
/// [large] is what differs: the senior's launcher scales everything up, and a
/// chat bubble sized for a guardian's phone is unreadable on the screen this
/// app exists to make legible.
class ConversationView extends ConsumerStatefulWidget {
  const ConversationView({
    super.key,
    required this.title,
    this.large = false,
    this.showQuota = true,
  });

  final String title;
  final bool large;

  /// The allowance is the guardian's to manage. Showing a senior a counter of
  /// how many times their family may write to them would be unkind and useless
  /// — their own replies are never counted anyway.
  final bool showQuota;

  @override
  ConsumerState<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends ConsumerState<ConversationView> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(messageControllerProvider.notifier).send(text);
      _controller.clear();
    } on MessageQuotaExceeded catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on SeniorLinkException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) setState(() => _error = '보내지 못했어요. 인터넷 연결을 확인해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Told, never awaited — the same rule the ring screen and the check-in
  /// follow. A platform channel is not obliged to reply, and a senior
  /// pressing a bubble must not be left holding a frozen screen because no
  /// Korean voice is installed.
  void _read(String? body) {
    final text = body?.trim();
    if (text == null || text.isEmpty) return;
    try {
      ref.read(speechReaderProvider).speak(text);
    } on Object {
      // Nothing on screen changes because of a speaker.
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(conversationProvider).value ?? const [];
    final quota = ref.watch(messageQuotaProvider).value;
    final scale = widget.large ? 1.25 : 1.0;

    return Column(
      children: [
        if (widget.showQuota && quota != null) _Quota(quota: quota),
        Expanded(
          child: messages.isEmpty
              ? _Empty(large: widget.large, title: widget.title)
              : ListView.builder(
                  key: ConversationKeys.list,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: messages.length,
                  itemBuilder: (context, i) => _Bubble(
                    message: messages[i],
                    // On the guardian's phone their own messages sit on the
                    // right; on the parent's phone theirs do. Same data, and
                    // each side sees itself where it expects to.
                    mine: widget.large
                        ? messages[i].isFromSenior
                        : !messages[i].isFromSenior,
                    scale: scale,
                    // Only on the parent's phone, and only on what came in.
                    // The guardian can read, and reading someone their own
                    // message back is noise.
                    onRead: widget.large && !messages[i].isFromSenior
                        ? () => _read(messages[i].body)
                        : null,
                  ),
                ),
        ),
        if (_error case final message?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              message,
              key: ConversationKeys.error,
              style: TextStyle(
                fontSize: 14 * scale,
                height: 1.4,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: ConversationKeys.field,
                    controller: _controller,
                    enabled: !_busy,
                    minLines: 1,
                    maxLines: 4,
                    style: TextStyle(fontSize: 16 * scale),
                    decoration: InputDecoration(
                      hintText: widget.large ? '여기에 쓰세요' : '메시지 보내기',
                      // Filled and rounded rather than a 1px box: the box
                      // fought the bubbles above it on both personas.
                      filled: true,
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1.6,
                        ),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: widget.large ? 16 : 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  key: ConversationKeys.send,
                  onPressed: _busy ? null : _send,
                  style: FilledButton.styleFrom(
                    minimumSize: Size(widget.large ? 96 : 72, 52 * scale),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    '보내기',
                    style: TextStyle(
                      fontSize: 15 * scale,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Quota extends StatelessWidget {
  const _Quota({required this.quota});

  final MessageQuota quota;

  @override
  Widget build(BuildContext context) {
    if (quota.unlimited) {
      return Padding(
        key: ConversationKeys.quota,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '안심 케어로 메시지를 제한 없이 보낼 수 있어요.',
            style: TextStyle(fontSize: 13, color: _muted(context)),
          ),
        ),
      );
    }
    return Padding(
      key: ConversationKeys.quota,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '이번 달 ${quota.textLeft}번 더 보낼 수 있어요',
            style: TextStyle(
              fontSize: 13,
              fontWeight: quota.isRunningLow
                  ? FontWeight.w700
                  : FontWeight.w400,
              color: _muted(context),
            ),
          ),
          // Offered when it starts to matter rather than only once they are
          // stuck — and phrased as what it buys, not as a wall.
          if (quota.isRunningLow)
            Text(
              '안심 케어를 시작하시면 제한 없이 보낼 수 있어요.',
              style: TextStyle(fontSize: 13, color: _muted(context)),
            ),
        ],
      ),
    );
  }
}

/// Secondary ink, taken from whichever persona is drawing this view — warm on
/// the senior's phone, cool on the guardian's. One widget draws both ends of
/// the conversation, so it cannot hold a colour of its own.
Color _muted(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.scale,
    this.onRead,
  });

  final FamilyMessage message;
  final bool mine;
  final double scale;

  /// Set on the parent's phone, for messages that came in. Null elsewhere.
  final VoidCallback? onRead;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bubble = Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        // Keyed by the message rather than by "a bubble": a shared key across
        // every row of a list is not a key.
        key: ValueKey(message.id),
        margin: const EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.symmetric(
          horizontal: 14 * scale,
          vertical: 10 * scale,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.72,
        ),
        decoration: BoxDecoration(
          color: mine ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message.body ?? '',
          style: TextStyle(
            fontSize: 16 * scale,
            height: 1.4,
            color: mine ? scheme.onPrimary : scheme.onSurface,
          ),
        ),
      ),
    );
    if (onRead == null) return bubble;

    // The whole bubble is the button, with a speaker beside it so a senior
    // knows it can be pressed. A small icon alone would be a target an
    // ageing hand misses; the bubble is the biggest thing on the row.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: InkWell(
            key: ConversationKeys.read(message.id),
            onTap: onRead,
            borderRadius: BorderRadius.circular(16),
            child: bubble,
          ),
        ),
        IconButton(
          onPressed: onRead,
          iconSize: 28 * scale,
          color: scheme.primary,
          tooltip: '읽어드리기',
          icon: const Icon(Icons.volume_up_rounded),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.large, required this.title});

  final bool large;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: ConversationKeys.empty,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          large ? '아직 주고받은 이야기가 없어요' : '$title께 첫 메시지를 보내 보세요',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: large ? 20 : 15,
            height: 1.5,
            color: const Color(0xFF6B6459),
          ),
        ),
      ),
    );
  }
}
