import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/api_models.dart';
import '../models/article_ui.dart';
import '../theme/app_colors.dart';
import 'audio_bulletin_player.dart';
import 'common.dart';
import 'simple_markdown.dart';
import 'state_views.dart';

/// Ana Sayfa kartları. Mobil ve web aynı kartları kullanır; web'de
/// [large] ile büyük ölçüler seçilir.

class _Card extends StatelessWidget {
  const _Card({required this.child, this.large = false});

  final Widget child;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(large ? 26 : 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(large ? 26 : 22),
        border: large ? Border.all(color: const Color(0xFF26262C)) : null,
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Günün manşeti kartı (görsel + başlık + özet + sesli bülten)
// ---------------------------------------------------------------------------
/// Varsayılan olarak tek haberi gösterir ("TOP STORY"). Ana sayfadaki "Latest
/// developments" kartı aynı düzeni kullanır: [label], [title] ve [summary]
/// sunucunun yazdığı başlık ve paragrafla doldurulur, görsel [article]'dan
/// (en üstteki haber) gelir.
class DailySummaryCard extends StatelessWidget {
  const DailySummaryCard({
    super.key,
    required this.article,
    this.large = false,
    this.horizontal = false,
    this.onTap,
    this.label = 'TOP STORY',
    this.title,
    this.summary,
    this.summaryMaxLines = 3,
    this.caption,
    this.onAsk,
  });

  final Article article;

  /// Kartın üstündeki etiket.
  final String label;

  /// Verilmezse haberin başlığı ve özeti.
  final String? title;
  final String? summary;
  final int summaryMaxLines;

  /// Görselin üstündeki yazı; verilmezse kategori · kaynak · zaman.
  final String? caption;

  /// Doluysa özetin altında "Ask WAI" düğmesi gösterilir.
  final VoidCallback? onAsk;

  /// Masaüstü ölçüleri.
  final bool large;

  /// Görsel solda, manşet ve oynatıcı sağda.
  final bool horizontal;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final header = Row(
      children: [
        const MintDot(),
        const SizedBox(width: 7),
        Text(
          label,
          style: GoogleFonts.inter(
            color: AppColors.mint,
            fontSize: large ? 12 : 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
        const Spacer(),
        Icon(
          Icons.headphones_outlined,
          size: large ? 18 : 16,
          color: AppColors.textBody,
        ),
        const SizedBox(width: 5),
        Text(
          'Audio Bulletin',
          style: GoogleFonts.inter(
            color: AppColors.textBody,
            fontSize: large ? 14 : 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );

    final image = ClipRRect(
      borderRadius: BorderRadius.circular(large ? 18 : 16),
      child: AspectRatio(
        aspectRatio: large ? 16 / 9 : 1.2,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ArticleCoverImage(image: article.image, fit: BoxFit.cover),
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xCC1A1A1F),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  caption ??
                      [
                        article.category,
                        article.source,
                        article.timeAgo,
                      ].where((s) => s.isNotEmpty).join(' · '),
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final titleText = Text(
      title ?? article.title,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.playfairDisplay(
        color: AppColors.textPrimary,
        fontSize: large ? (horizontal ? 28 : 26) : 20,
        fontWeight: FontWeight.w500,
        height: 1.35,
      ),
    );

    final summaryText = Text(
      summary ?? article.summary,
      maxLines: summaryMaxLines,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.sourceSerif4(
        color: AppColors.textBody,
        fontSize: large ? 16 : 14.5,
        height: 1.55,
      ),
    );

    Widget tappable(Widget child) => onTap == null
        ? child
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(onTap: onTap, child: child),
          );

    if (horizontal) {
      return _Card(
        large: large,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 11, child: tappable(image)),
                const SizedBox(width: 28),
                Expanded(
                  flex: 9,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      tappable(titleText),
                      const SizedBox(height: 12),
                      summaryText,
                      if (onAsk != null) ...[
                        const SizedBox(height: 14),
                        _AskWaiButton(onTap: onAsk!),
                      ],
                      const SizedBox(height: 20),
                      const AudioBulletinPlayer(),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return _Card(
      large: large,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          SizedBox(height: large ? 16 : 12),
          tappable(image),
          SizedBox(height: large ? 22 : 18),
          tappable(titleText),
          SizedBox(height: large ? 10 : 8),
          summaryText,
          if (onAsk != null) ...[
            SizedBox(height: large ? 14 : 10),
            _AskWaiButton(onTap: onAsk!),
          ],
          SizedBox(height: large ? 18 : 14),
          const AudioBulletinPlayer(),
        ],
      ),
    );
  }
}

/// "Ask WAI about this": kartın içeriğiyle WAI sohbetini açar.
class _AskWaiButton extends StatelessWidget {
  const _AskWaiButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: AppColors.accentLight,
              ),
              const SizedBox(width: 8),
              Text(
                'Ask WAI about this',
                style: GoogleFonts.inter(
                  color: AppColors.accentLight,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kaynak karşılaştırma özeti (synthesize)
// ---------------------------------------------------------------------------
class WrittenSummaryCard extends StatelessWidget {
  const WrittenSummaryCard({
    super.key,
    required this.sources,
    this.brief,
    this.loading = false,
    this.error,
    this.onRetry,
    this.onReadMore,
    this.large = false,
    this.previewHeight,
    this.title = 'Cross-Source Brief',
    this.loadingMessage = "WAI is comparing today's top stories…",
    this.loadingHint = 'This can take up to 30 seconds.',
  });

  /// Kart başlığı (kişisel özette ör. "Daily Brief · AI").
  final String title;
  final String loadingMessage;
  final String loadingHint;

  /// Karşılaştırılan haberler.
  final List<Article> sources;
  final String? brief;
  final bool loading;
  final Object? error;
  final VoidCallback? onRetry;

  /// Doluysa özet kısaltılarak gösterilir ve "Read more" bunu çağırır.
  final VoidCallback? onReadMore;
  final bool large;

  /// Kısaltılmış önizlemenin yüksekliği.
  final double? previewHeight;

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (error != null) {
      body = ErrorView(error: error!, onRetry: onRetry, compact: true);
    } else if (loading || brief == null) {
      body = LoadingView(
        message: loadingMessage,
        hint: loadingHint,
        padding: 36,
      );
    } else if (onReadMore != null) {
      body = SizedBox(
        height: previewHeight ?? (large ? 420 : 320),
        child: ClipRect(
          child: ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Colors.white, Colors.transparent],
              stops: [0, 0.78, 1],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: SimpleMarkdown(brief!, fontSize: large ? 16 : 15),
            ),
          ),
        ),
      );
    } else {
      body = SimpleMarkdown(brief!, fontSize: large ? 16 : 15);
    }

    return _Card(
      large: large,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: large ? 22 : 20,
                color: AppColors.textBody,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    maxLines: 1,
                    style: GoogleFonts.playfairDisplay(
                      color: AppColors.textPrimary,
                      fontSize: large ? 22 : 19,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              if (sources.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  '${sources.length} source${sources.length == 1 ? '' : 's'}',
                  style: GoogleFonts.inter(
                    color: AppColors.textBody,
                    fontSize: large ? 12 : 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in sources)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.quoteBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    a.source,
                    style: GoogleFonts.inter(
                      color: AppColors.accentLight,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: large ? 18 : 14),
          body,
          if (brief != null && error == null && onReadMore != null) ...[
            SizedBox(height: large ? 14 : 10),
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: onReadMore,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Read full brief',
                        style: GoogleFonts.inter(
                          color: AppColors.accentLight,
                          fontSize: large ? 15 : 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: AppColors.accentLight,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Haber özetleri listesi (ana sayfadaki "Daily Brief")
// ---------------------------------------------------------------------------
/// "Latest developments" kartının yazıldığı haberler ve her birinin kendi
/// kısa özeti (kişiye göre yeniden yazılmaz).
class StorySummariesCard extends StatelessWidget {
  const StorySummariesCard({
    super.key,
    required this.articles,
    this.title = 'Daily Brief',
    this.subtitle = 'The stories behind your latest developments',
    this.loading = false,
    this.error,
    this.onRetry,
    this.onOpen,
    this.large = false,
    this.height,
  });

  final List<Article> articles;
  final String title;
  final String subtitle;
  final bool loading;
  final Object? error;
  final VoidCallback? onRetry;
  final ValueChanged<Article>? onOpen;
  final bool large;

  /// Liste bu yükseklikte kaydırılır; verilmezse tamamı gösterilir.
  final double? height;

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (error != null && articles.isEmpty) {
      body = ErrorView(error: error!, onRetry: onRetry, compact: true);
    } else if (articles.isEmpty) {
      body = LoadingView(
        message: loading
            ? 'WAI is picking the stories that matter to you…'
            : 'No stories yet.',
        padding: 36,
      );
    } else {
      final list = ListView.separated(
        padding: EdgeInsets.zero,
        shrinkWrap: height == null,
        physics: height == null ? const NeverScrollableScrollPhysics() : null,
        itemCount: articles.length,
        separatorBuilder: (_, _) =>
            const Divider(color: AppColors.border, height: 28),
        itemBuilder: (context, i) => _StorySummary(
          article: articles[i],
          large: large,
          onTap: onOpen == null ? null : () => onOpen!(articles[i]),
        ),
      );
      body = height == null ? list : SizedBox(height: height, child: list);
    }

    final count = articles.length;
    return _Card(
      large: large,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: large ? 22 : 20,
                color: AppColors.textBody,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.playfairDisplay(
                    color: AppColors.textPrimary,
                    fontSize: large ? 22 : 19,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (count > 0)
                Text(
                  count == 1 ? '1 story' : '$count stories',
                  style: GoogleFonts.inter(
                    color: AppColors.textBody,
                    fontSize: large ? 12 : 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              color: AppColors.textMuted,
              fontSize: large ? 13 : 12,
            ),
          ),
          SizedBox(height: large ? 18 : 14),
          body,
        ],
      ),
    );
  }
}

class _StorySummary extends StatelessWidget {
  const _StorySummary({required this.article, this.large = false, this.onTap});

  final Article article;
  final bool large;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          [
            article.source,
            article.timeAgo,
          ].where((s) => s.isNotEmpty).join(' · '),
          style: GoogleFonts.inter(
            color: AppColors.accentLight,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          article.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: AppColors.textPrimary,
            fontSize: large ? 15 : 14,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
        if (article.summary.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            article.summary,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.sourceSerif4(
              color: AppColors.textBody,
              fontSize: large ? 14.5 : 13.5,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
    if (onTap == null) return content;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: content),
    );
  }
}
