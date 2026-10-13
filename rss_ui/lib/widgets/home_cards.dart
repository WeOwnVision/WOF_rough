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
class DailySummaryCard extends StatelessWidget {
  const DailySummaryCard({
    super.key,
    required this.article,
    this.large = false,
    this.horizontal = false,
    this.onTap,
  });

  final Article article;

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
          'TOP STORY',
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
            Image.asset(article.image, fit: BoxFit.cover),
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

    final title = Text(
      article.title,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.playfairDisplay(
        color: AppColors.textPrimary,
        fontSize: large ? (horizontal ? 28 : 26) : 20,
        fontWeight: FontWeight.w500,
        height: 1.35,
      ),
    );

    final summary = Text(
      article.summary,
      maxLines: 3,
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
                      tappable(title),
                      const SizedBox(height: 12),
                      summary,
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
          tappable(title),
          SizedBox(height: large ? 10 : 8),
          summary,
          SizedBox(height: large ? 18 : 14),
          const AudioBulletinPlayer(),
        ],
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
  });

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
      body = const LoadingView(
        message: "WAI is comparing today's top stories…",
        hint: 'This can take up to 30 seconds.',
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
                    'Cross-Source Brief',
                    maxLines: 1,
                    style: GoogleFonts.playfairDisplay(
                      color: AppColors.textPrimary,
                      fontSize: large ? 22 : 19,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${sources.length} sources',
                style: GoogleFonts.inter(
                  color: AppColors.textBody,
                  fontSize: large ? 12 : 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
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
