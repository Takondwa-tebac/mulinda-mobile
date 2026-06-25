import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/providers/auth_controller.dart';
import '../../subscription/data/subscription_models.dart';
import '../../subscription/widgets/premium_lock.dart';
import '../data/coach_chart_repository.dart';
import '../data/coach_repository.dart';
import '../widgets/coach_chart_widget.dart';

class _Msg {
  _Msg({
    required this.text,
    required this.fromUser,
    this.isStreaming = false,
    this.charts = const [],
  });
  final String text;
  final bool fromUser;
  final bool isStreaming;
  final List<Future<Map<String, dynamic>?>> charts;
}

class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  final _messages = <_Msg>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  String? _conversationId;
  bool _sending = false;
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final history = await ref.read(coachRepositoryProvider).loadHistory();
      if (!mounted) return;
      if (history != null && history.messages.isNotEmpty) {
        setState(() {
          _conversationId = history.conversationId;
          for (final m in history.messages) {
            _messages.add(_Msg(text: m.content, fromUser: m.role == 'user'));
          }
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (_) {
      // History failure is non-fatal — start fresh.
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _send(String text) async {
    final message = text.trim();
    if (message.isEmpty || _sending) return;

    setState(() {
      _messages.add(_Msg(text: message, fromUser: true));
      // Placeholder assistant bubble — spinner until first token.
      _messages.add(_Msg(text: '', fromUser: false, isStreaming: true));
      _sending = true;
    });
    _input.clear();
    _scrollToBottom();

    try {
      final stream = ref.read(coachRepositoryProvider).sendStream(
            message,
            conversationId: _conversationId,
          );

      await for (final chunk in stream) {
        if (!mounted) return;
        if (chunk.isDone) {
          setState(() {
            _conversationId = chunk.conversationId ?? _conversationId;
            final last = _messages.last;
            _messages[_messages.length - 1] =
                _Msg(text: last.text, fromUser: false, charts: last.charts);
            _sending = false;
          });
          _scrollToBottom();
        } else if (chunk.chartHint != null) {
          final hint = chunk.chartHint!;
          final future = ref
              .read(coachChartRepositoryProvider)
              .fetchChart(hint.kind, params: hint.params);
          setState(() {
            final last = _messages.last;
            _messages[_messages.length - 1] = _Msg(
              text: last.text,
              fromUser: false,
              isStreaming: true,
              charts: [...last.charts, future],
            );
          });
        } else if (chunk.text != null && chunk.text!.isNotEmpty) {
          setState(() {
            final last = _messages.last;
            _messages[_messages.length - 1] = _Msg(
              text: last.text + chunk.text!,
              fromUser: false,
              isStreaming: true,
              charts: last.charts,
            );
          });
          // Scroll only when at or near the bottom so we don't
          // interrupt the user if they're reading earlier messages.
          _scrollToBottomIfNear();
        }
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      _handleSendError(e.displayMessage);
    } catch (_) {
      if (!mounted) return;
      _handleSendError('coach.error'.tr());
    }
  }

  void _handleSendError(String message) {
    setState(() {
      _sending = false;
      if (_messages.isNotEmpty && !_messages.last.fromUser) {
        final last = _messages.last;
        if (last.text.isEmpty) {
          _messages.removeLast(); // Remove empty placeholder.
        } else {
          // Keep partial response but stop streaming indicator.
          _messages[_messages.length - 1] =
              _Msg(text: last.text, fromUser: false);
        }
      }
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _scrollToBottomIfNear() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final distanceFromBottom = pos.maxScrollExtent - pos.pixels;
    if (distanceFromBottom < 120) _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    // Coach is premium — gate the whole screen behind an active subscription/trial.
    final entitled =
        ref.watch(currentUserProvider)?.can(Entitlements.coachChat) ?? false;
    if (!entitled) {
      return Scaffold(
        appBar: AppBar(title: Text('coach.title'.tr())),
        body: PremiumLockView(
          title: 'coach.lockedTitle'.tr(),
          message: 'coach.lockedMessage'.tr(),
          icon: Icons.auto_awesome,
        ),
      );
    }

    final showEmpty = !_loadingHistory && _messages.isEmpty && !_sending;

    return Scaffold(
      appBar: AppBar(title: Text('coach.title'.tr())),
      body: Column(
        children: [
          Expanded(
            child: _loadingHistory
                ? const Center(child: CircularProgressIndicator())
                : showEmpty
                    ? _Empty(onTap: _send)
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) =>
                            _Bubble(msg: _messages[i]),
                      ),
          ),
          _InputBar(
            controller: _input,
            enabled: !_sending && !_loadingHistory,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Message bubble
// ---------------------------------------------------------------------------

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg});
  final _Msg msg;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = msg.fromUser ? scheme.primary : scheme.surfaceContainerHigh;
    final fg = msg.fromUser ? scheme.onPrimary : scheme.onSurface;
    final hasCharts = !msg.fromUser && msg.charts.isNotEmpty;

    final bubble = Align(
      alignment: msg.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: hasCharts ? 4 : 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(msg.fromUser ? 16 : 4),
            bottomRight: Radius.circular(msg.fromUser ? 4 : 16),
          ),
        ),
        child: msg.isStreaming && msg.text.isEmpty
            ? SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: fg.withValues(alpha: 0.6),
                ),
              )
            : Text(msg.text, style: TextStyle(color: fg, height: 1.4)),
      ),
    );

    if (!hasCharts) return bubble;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bubble,
          ...msg.charts.map((f) => _ChartFuture(future: f)),
        ],
      ),
    );
  }
}

class _ChartFuture extends StatelessWidget {
  const _ChartFuture({required this.future});
  final Future<Map<String, dynamic>?> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final data = snapshot.data;
        if (data == null) return const SizedBox.shrink();
        return CoachChartWidget(data: data);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Empty / welcome state
// ---------------------------------------------------------------------------

class _Empty extends StatelessWidget {
  const _Empty({required this.onTap});
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final suggestions = ['coach.s1'.tr(), 'coach.s2'.tr(), 'coach.s3'.tr()];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: const Icon(Icons.auto_awesome, size: 30),
            ),
            const SizedBox(height: 16),
            Text('coach.emptyTitle'.tr(),
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('coach.emptySubtitle'.tr(),
                textAlign: TextAlign.center,
                style:
                    text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: suggestions
                  .map((s) => ActionChip(label: Text(s), onPressed: () => onTap(s)))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Input bar
// ---------------------------------------------------------------------------

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final void Function(String) onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: onSend,
                decoration: InputDecoration(
                  hintText: 'coach.hint'.tr(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: enabled ? () => onSend(controller.text) : null,
              icon: const Icon(Icons.send_rounded),
              style: IconButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                minimumSize: const Size(52, 52),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
