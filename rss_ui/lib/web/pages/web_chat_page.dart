import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/api_models.dart';
import '../../models/article_ui.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import '../../widgets/state_views.dart';
import '../widgets/article_dialog.dart';
import '../widgets/web_ui.dart';

/// WAI haber asistanı sohbeti.
class WebChatPage extends StatelessWidget {
  const WebChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => LayoutBuilder(
          builder: (context, c) {
            final showContext = c.maxWidth >= 1080;
            final news = state.activeThreadArticle;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 290, child: _ThreadList(state: state)),
                const SizedBox(width: 20),
                Expanded(child: _ChatPanel(state: state)),
                if (showContext) ...[
                  const SizedBox(width: 20),
                  SizedBox(
                    width: 320,
                    child: news == null
                        ? const _CapabilitiesPanel()
                        : _ContextPanel(news: news),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sohbet listesi
// ---------------------------------------------------------------------------
class _ThreadList extends StatelessWidget {
  const _ThreadList({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final ids = state.threads.keys.toList().reversed.toList();
    return PanelCard(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Text(
                  'Chats',
                  style: GoogleFonts.playfairDisplay(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: 'New chat',
                  child: Hoverable(
                    onTap: state.startNewChat,
                    builder: (context, hovered) => Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: hovered
                            ? AppColors.accentLight
                            : AppColors.accent.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: hovered ? onAccent : AppColors.accentLight,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ids.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'No chats yet. Pick a story to start one.',
                      style: GoogleFonts.inter(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: ids.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, i) {
                      final id = ids[i];
                      final news = state.articleById(id);
                      final messages = state.threads[id]!;
                      final last = messages.lastWhere(
                        (m) => m.text.isNotEmpty,
                        orElse: () => messages.last,
                      );
                      return _ThreadTile(
                        title: news?.title ?? 'Story',
                        preview: last.text.isEmpty ? 'Story shared' : last.text,
                        time: formatTime(last.time),
                        image: news?.image,
                        selected: id == state.activeThreadId,
                        onTap: () => state.openThread(id),
                      );
                    },
                  ),
          ),
          const Divider(color: AppColors.border, height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'To send a story to WAI, use the "Ask WAI" button in Feed or '
              'Discover.',
              style: GoogleFonts.inter(
                color: AppColors.textMuted,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    required this.title,
    required this.preview,
    required this.time,
    required this.image,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String preview;
  final String time;
  final String? image;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.14)
              : (hovered ? AppColors.surfaceAlt : Colors.transparent),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: image == null
                  ? const GradientOrb(
                      size: 44,
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    )
                  : Image.asset(
                      image!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: selected
                                ? AppColors.accentLight
                                : AppColors.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        time,
                        style: GoogleFonts.inter(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sohbet paneli
// ---------------------------------------------------------------------------
class _ChatPanel extends StatefulWidget {
  const _ChatPanel({required this.state});

  final AppState state;

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  static const _suggestions = [
    'Simplify this',
    'Why does it matter?',
    "What's the counterargument?",
    'What are the sources?',
  ];

  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  int _lastSignature = -1;
  String? _lastThread;

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final value = text ?? _input.text;
    if (value.trim().isEmpty) return;
    widget.state.send(value);
    _input.clear();
    _inputFocus.requestFocus();
  }

  void _scrollToEndIfNeeded() {
    final state = widget.state;
    final messages = state.activeMessages;
    final signature =
        messages.length * 100000 +
        (messages.isEmpty ? 0 : messages.last.text.length);
    if (signature == _lastSignature && state.activeThreadId == _lastThread) {
      return;
    }
    final jump = state.activeThreadId != _lastThread;
    _lastSignature = signature;
    _lastThread = state.activeThreadId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (jump) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(
          end,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    if (state.activeThreadId == null) return _StartPanel(state: state);
    final messages = state.activeMessages;
    final busy = state.waiTyping;
    _scrollToEndIfNeeded();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _ChatHeader(news: state.activeThreadArticle),
          const Divider(color: AppColors.border, height: 1),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
              children: [
                for (final m in messages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _MessageView(message: m, state: state),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in _suggestions)
                    PillButton(
                      label: s,
                      selected: false,
                      dense: true,
                      onTap: () => busy ? null : _send(s),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Ask by voice',
                    onPressed: () {},
                    icon: const Icon(
                      Icons.mic_none_rounded,
                      color: AppColors.textMuted,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _inputFocus,
                      autofocus: true,
                      readOnly: busy,
                      onSubmitted: (_) => busy ? null : _send(),
                      cursorColor: AppColors.accentLight,
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                      ),
                      decoration: InputDecoration(
                        hintText: busy
                            ? 'WAI is answering…'
                            : 'Ask WAI anything about this story…',
                        hintStyle: GoogleFonts.inter(
                          color: AppColors.textMuted,
                          fontSize: 15,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Send (Enter)',
                    child: Hoverable(
                      onTap: busy ? null : _send,
                      builder: (context, hovered) => Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hovered
                              ? AppColors.textPrimary
                              : AppColors.accentLight,
                        ),
                        child: const Icon(
                          Icons.arrow_upward_rounded,
                          color: onAccent,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.news});

  final Article? news;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.accentDeep.withValues(alpha: 0.16),
            AppColors.surface,
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'WAI',
                  style: GoogleFonts.playfairDisplay(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: AppColors.accentLight,
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  news?.title ?? 'Story',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.mint,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'News assistant · online',
                      style: GoogleFonts.inter(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message, required this.state});

  final ChatMessage message;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (message.article != null) return _SentNews(news: message.article!);
    if (message.role == ChatRole.user) return _UserBubble(message: message);
    return _AssistantBubble(message: message, state: state);
  }
}

class _SentNews extends StatelessWidget {
  const _SentNews({required this.news});

  final Article news;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.reply_rounded,
              size: 14,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              'Shared story',
              style: GoogleFonts.inter(
                color: AppColors.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Hoverable(
            onTap: () => showArticleDialog(context, news),
            builder: (context, hovered) => Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: hovered ? AppColors.quoteBg : AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      news.image,
                      width: 76,
                      height: 60,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          news.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.playfairDisplay(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          news.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.sourceSerif4(
                            color: AppColors.textBody,
                            fontSize: 13.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.accentLight,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: SelectableText(
              message.text,
              style: GoogleFonts.inter(
                color: onAccent,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          formatTime(message.time),
          style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.message, required this.state});

  final ChatMessage message;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final waiting = message.streaming && message.text.isEmpty;
    final error = message.isError;

    final Widget content;
    if (waiting) {
      content = const _TypingIndicator();
    } else if (error) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.dislike,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              message.text,
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      );
    } else {
      content = SelectableText(
        message.streaming ? '${message.text}▍' : message.text,
        style: GoogleFonts.sourceSerif4(
          color: AppColors.textPrimary,
          fontSize: 16.5,
          height: 1.65,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const GradientOrb(
          size: 34,
          child: Icon(
            Icons.auto_awesome_rounded,
            size: 16,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: error
                        ? AppColors.dislike.withValues(alpha: 0.10)
                        : AppColors.surfaceAlt,
                    border: error
                        ? Border.all(
                            color: AppColors.dislike.withValues(alpha: 0.4),
                          )
                        : null,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                  ),
                  child: content,
                ),
                if (!message.streaming) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (error)
                        _MiniAction(
                          icon: Icons.refresh_rounded,
                          label: 'Retry',
                          onTap: () => state.retry(message),
                        )
                      else ...[
                        _MiniAction(
                          icon: message.helpful
                              ? Icons.thumb_up_alt_rounded
                              : Icons.thumb_up_alt_outlined,
                          label: 'Helpful',
                          active: message.helpful,
                          onTap: () => state.toggleHelpful(message),
                        ),
                        const SizedBox(width: 6),
                        _MiniAction(
                          icon: Icons.copy_rounded,
                          label: 'Copy',
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: message.text),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                behavior: SnackBarBehavior.floating,
                                width: 260,
                                backgroundColor: AppColors.surfaceAlt,
                                content: Text(
                                  'Answer copied to clipboard',
                                  style: GoogleFonts.inter(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                      const SizedBox(width: 10),
                      Text(
                        formatTime(message.time),
                        style: GoogleFonts.inter(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Henüz sohbet seçilmediğinde: haber seçip WAI'ye sorma ekranı.
class _StartPanel extends StatefulWidget {
  const _StartPanel({required this.state});

  final AppState state;

  @override
  State<_StartPanel> createState() => _StartPanelState();
}

class _StartPanelState extends State<_StartPanel> {
  @override
  void initState() {
    super.initState();
    widget.state.ensureFeed();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final Widget list;
    if (state.feed.isEmpty && state.feedError != null) {
      list = ErrorView(error: state.feedError!, onRetry: state.loadMoreFeed);
    } else if (state.feed.isEmpty) {
      list = const LoadingView(message: 'Loading stories…');
    } else {
      list = ListView.separated(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        itemCount: state.feed.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final a = state.feed[i];
          return Hoverable(
            onTap: () => state.askAbout(a),
            builder: (context, hovered) => AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hovered ? AppColors.surfaceAlt : AppColors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hovered
                      ? AppColors.accent.withValues(alpha: 0.45)
                      : AppColors.border,
                ),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      a.image,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OverlineLabel(a.category, color: AppColors.mint),
                        const SizedBox(height: 4),
                        Text(
                          a.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.playfairDisplay(
                            color: AppColors.textPrimary,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.forum_outlined,
                    size: 20,
                    color: hovered
                        ? AppColors.accentLight
                        : AppColors.textMuted,
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pick a story to ask WAI about',
                  style: GoogleFonts.playfairDisplay(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'WAI answers strictly from the story you choose — ask it to '
                  'simplify, explain why it matters, or find what is missing.',
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: list),
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: hovered || active ? AppColors.surfaceAlt : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: active ? AppColors.like : AppColors.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                color: active ? AppColors.like : AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(16),
            ),
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accentLight.withValues(
                          alpha: ((_c.value * 3 - i) % 3) < 1 ? 1 : 0.35,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'WAI is thinking…',
            style: GoogleFonts.inter(
              color: AppColors.textMuted,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sağ panel
// ---------------------------------------------------------------------------
class _ContextPanel extends StatelessWidget {
  const _ContextPanel({required this.news});

  final Article news;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: PanelCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const OverlineLabel('Chat context'),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Image.asset(news.image, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 14),
            OverlineLabel(news.category, color: AppColors.mint),
            const SizedBox(height: 6),
            Text(
              news.title,
              style: GoogleFonts.playfairDisplay(
                color: AppColors.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              news.summary,
              style: GoogleFonts.sourceSerif4(
                color: AppColors.textBody,
                fontSize: 14.5,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              sourceLine(news),
              style: GoogleFonts.inter(
                color: AppColors.textMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: WebButton(
                    label: 'Open story',
                    icon: Icons.open_in_new_rounded,
                    onTap: () => showArticleDialog(context, news),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Center(child: BookmarkButton(news)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CapabilitiesPanel extends StatelessWidget {
  const _CapabilitiesPanel();

  static const _items = [
    (
      Icons.compress_rounded,
      'Simplify',
      'Explains complex stories in a single paragraph.',
    ),
    (
      Icons.balance_rounded,
      'Opposing views',
      'Summarizes the arguments of each side.',
    ),
    (Icons.link_rounded, 'Source tracking', 'Shows where a story comes from.'),
    (
      Icons.headphones_outlined,
      'Audio brief',
      'Turns answers into an audio bulletin.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OverlineLabel('What can WAI do?'),
          const SizedBox(height: 16),
          for (final (icon, title, body) in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: AppColors.accentLight),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.inter(
                            color: AppColors.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          body,
                          style: GoogleFonts.inter(
                            color: AppColors.textMuted,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
