import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/api_models.dart';
import '../../models/article_ui.dart';
import '../../services/api_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import '../../widgets/state_views.dart';
import 'web_ui.dart';

/// Haber detay penceresi: tam metin, kaynak bağlantısı ve yorumlar.
Future<void> showArticleDialog(BuildContext context, Article article) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    builder: (context) => _ArticleDialog(article: article),
  );
}

class _ArticleDialog extends StatefulWidget {
  const _ArticleDialog({required this.article});

  final Article article;

  @override
  State<_ArticleDialog> createState() => _ArticleDialogState();
}

class _ArticleDialogState extends State<_ArticleDialog> {
  final _state = AppState.instance;
  final _commentCtrl = TextEditingController();

  late Future<Article> _detail;
  late Future<List<ArticleComment>> _comments;
  final List<ArticleComment> _posted = [];
  String _selection = '';
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _loadDetail();
    _loadComments();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  void _loadDetail() => _detail = _state.loadDetail(widget.article.id);

  void _loadComments() {
    _posted.clear();
    _comments = _state.api.getComments(widget.article.id);
  }

  Future<void> _openOriginal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, webOnlyWindowName: '_blank');
  }

  Future<void> _postComment() async {
    final user = _state.user;
    final text = _commentCtrl.text.trim();
    if (user == null || text.isEmpty || _posting) return;
    setState(() => _posting = true);
    try {
      final comment = await _state.api.postComment(
        widget.article.id,
        user: user,
        commentText: text,
        selectedText: _selection,
      );
      _commentCtrl.clear();
      setState(() {
        _posted.add(comment);
        _selection = '';
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.userMessage)));
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.article;
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 880),
        // Dialog kendi Scaffold'unda değil; SnackBar için bir tane ekle.
        child: ScaffoldMessenger(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(a),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(36, 26, 36, 32),
                    child: FutureBuilder<Article>(
                      future: _detail,
                      builder: (context, snap) {
                        final detail = snap.data;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _meta(detail ?? a),
                            const SizedBox(height: 14),
                            Text(
                              a.title,
                              style: GoogleFonts.playfairDisplay(
                                color: AppColors.textPrimary,
                                fontSize: 32,
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                              ),
                            ),
                            if ((detail ?? a).tldr != null) ...[
                              const SizedBox(height: 20),
                              _tldr((detail ?? a).tldr!),
                            ],
                            const SizedBox(height: 22),
                            if (snap.hasError)
                              ErrorView(
                                error: snap.error!,
                                compact: true,
                                onRetry: () => setState(_loadDetail),
                              )
                            else if (detail == null)
                              const LoadingView(
                                message: 'Loading the full story…',
                                padding: 24,
                              )
                            else
                              _body(detail),
                            const SizedBox(height: 26),
                            _actions(detail ?? a),
                            const SizedBox(height: 32),
                            const Divider(color: AppColors.border),
                            const SizedBox(height: 20),
                            _commentsSection(),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(Article a) {
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 2.6,
          child: Image.asset(a.image, fit: BoxFit.cover),
        ),
        Positioned(left: 20, top: 20, child: CategoryBadge(a.category)),
        Positioned(
          right: 16,
          top: 16,
          child: CircleIconButton(
            icon: Icons.close_rounded,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }

  Widget _meta(Article a) {
    final parts = [
      a.source,
      if (a.author != null && a.author!.isNotEmpty) 'by ${a.author}',
      if (a.timeAgo.isNotEmpty) a.timeAgo,
      if (a.readMinutes != null) '${a.readMinutes} min read',
    ];
    return Row(
      children: [
        const Icon(Icons.verified_rounded, size: 16, color: AppColors.mint),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            parts.join(' · '),
            style: GoogleFonts.inter(
              color: AppColors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _tldr(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.quoteBg,
        borderRadius: BorderRadius.circular(14),
        border: const Border(
          left: BorderSide(color: AppColors.accent, width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OverlineLabel('TL;DR', color: AppColors.accentLight),
          const SizedBox(height: 8),
          Text(
            text,
            style: GoogleFonts.sourceSerif4(
              color: AppColors.textPrimary,
              fontSize: 16,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(Article detail) {
    final text = detail.cleanText?.trim() ?? '';
    if (text.isEmpty) {
      return Text(
        'The full text is not available for this story.',
        style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          text,
          style: GoogleFonts.sourceSerif4(
            color: AppColors.textBody,
            fontSize: 18,
            height: 1.7,
          ),
          onSelectionChanged: (sel, _) {
            final picked = sel.isValid && !sel.isCollapsed
                ? sel.textInside(text).trim()
                : '';
            if (picked.isNotEmpty && picked != _selection) {
              setState(() => _selection = picked);
            }
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(
              Icons.format_quote_rounded,
              size: 15,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              'Select a passage to comment on it.',
              style: GoogleFonts.inter(
                color: AppColors.textMuted,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _actions(Article a) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) => Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          WebButton(
            label: 'Ask WAI',
            icon: Icons.forum_outlined,
            onTap: () {
              Navigator.of(context).pop();
              _state.askAbout(a);
            },
          ),
          WebButton(
            label: _state.isSaved(a.id) ? 'Saved' : 'Save',
            icon: _state.isSaved(a.id)
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            primary: false,
            onTap: () => _state.toggleSaved(a.id),
          ),
          WebButton(
            label: _state.isLiked(a.id) ? 'Liked' : 'Like',
            icon: _state.isLiked(a.id)
                ? Icons.thumb_up_alt_rounded
                : Icons.thumb_up_alt_outlined,
            primary: false,
            color: _state.isLiked(a.id) ? AppColors.like : null,
            onTap: () => _state.toggleLiked(a.id),
          ),
          if (a.url.isNotEmpty)
            WebButton(
              label: 'Read original',
              icon: Icons.open_in_new_rounded,
              primary: false,
              onTap: () => _openOriginal(a.url),
            ),
        ],
      ),
    );
  }

  Widget _commentsSection() {
    return FutureBuilder<List<ArticleComment>>(
      future: _comments,
      builder: (context, snap) {
        final comments = [...?snap.data, ..._posted];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              snap.hasData ? 'Comments (${comments.length})' : 'Comments',
              style: GoogleFonts.playfairDisplay(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            _commentInput(),
            const SizedBox(height: 18),
            if (snap.hasError)
              ErrorView(
                error: snap.error!,
                compact: true,
                onRetry: () => setState(_loadComments),
              )
            else if (!snap.hasData)
              const LoadingView(padding: 16)
            else if (comments.isEmpty)
              Text(
                'No comments yet. Be the first to share your take.',
                style: GoogleFonts.inter(
                  color: AppColors.textMuted,
                  fontSize: 13.5,
                ),
              )
            else
              for (final c in comments.reversed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CommentTile(comment: c),
                ),
          ],
        );
      },
    );
  }

  Widget _commentInput() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selection.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 3, height: 36, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '“$_selection”',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.sourceSerif4(
                      color: AppColors.textBody,
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove quote',
                  onPressed: () => setState(() => _selection = ''),
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              UserAvatar(size: 34, url: _state.user?.avatarUrl),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _commentCtrl,
                  onSubmitted: (_) => _postComment(),
                  minLines: 1,
                  maxLines: 4,
                  cursorColor: AppColors.accentLight,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: _selection.isEmpty
                        ? 'Add a comment…'
                        : 'Comment on the selected passage…',
                    hintStyle: GoogleFonts.inter(
                      color: AppColors.textMuted,
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _posting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accentLight,
                      ),
                    )
                  : WebButton(label: 'Post', onTap: _postComment),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});

  final ArticleComment comment;

  @override
  Widget build(BuildContext context) {
    final created = comment.createdAt?.toLocal();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UserAvatar(size: 34, url: comment.avatarUrl),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    comment.username.isEmpty ? 'Reader' : comment.username,
                    style: GoogleFonts.inter(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (created != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      formatTime(created),
                      style: GoogleFonts.inter(
                        color: AppColors.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
              if (comment.selectedText != null &&
                  comment.selectedText!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 4, 8, 4),
                  decoration: const BoxDecoration(
                    border: Border(
                      left: BorderSide(color: AppColors.accent, width: 3),
                    ),
                  ),
                  child: Text(
                    '“${comment.selectedText}”',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.sourceSerif4(
                      color: AppColors.textMuted,
                      fontSize: 13.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                comment.comment,
                style: GoogleFonts.inter(
                  color: AppColors.textBody,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
