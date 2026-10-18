import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/api_models.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/home_cards.dart';
import '../../widgets/simple_markdown.dart';
import '../../widgets/state_views.dart';
import '../widgets/article_dialog.dart';
import '../widgets/web_ui.dart';

/// Web Ana Sayfa: manşet, kaynak karşılaştırma özeti, gündem ızgarası,
/// kaydedilenler ve okuma serisi.
class WebHomePage extends StatefulWidget {
  const WebHomePage({super.key});

  @override
  State<WebHomePage> createState() => _WebHomePageState();
}

class _WebHomePageState extends State<WebHomePage> {
  final _state = AppState.instance;

  @override
  void initState() {
    super.initState();
    // Akışı ve ardından ilk haberlerin karşılaştırmalı özetini yükle.
    _state.loadBrief();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        final feed = _state.feed;
        if (feed.isEmpty) {
          if (_state.feedError != null) {
            return ErrorView(
              error: _state.feedError!,
              onRetry: () =>
                  _state.refreshFeed().then((_) => _state.loadBrief()),
            );
          }
          if (_state.feedLoading) {
            return const LoadingView(message: 'Loading the latest stories…');
          }
          return const EmptyView(
            icon: Icons.inbox_outlined,
            title: 'No stories yet',
            message: 'New stories will appear here as soon as they arrive.',
          );
        }
        return _content(feed);
      },
    );
  }

  Widget _content(List<Article> feed) {
    final top = feed.first;
<<<<<<< HEAD
=======
    final personalBrief = _state.hasServerUser;
    // Giriş yapılmışsa üstteki haberler "Latest developments" kartında ve
    // Daily Brief listesinde; ızgara onlardan sonrakilerle devam eder.
    final briefStories = personalBrief ? _state.briefArticles.length : 1;
>>>>>>> ba5d700 (All system base developed for system design at backend server. Also Flutter Frontend developed.)
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 56),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 1040;
              final columns = wide ? 4 : 3;
<<<<<<< HEAD
              final daily = DailySummaryCard(
                article: top,
                large: true,
                horizontal: !wide,
                onTap: () => showArticleDialog(context, top),
              );
              final brief = WrittenSummaryCard(
                sources: _state.briefArticles,
                brief: _state.brief,
                loading: _state.briefLoading,
                error: _state.briefError,
                onRetry: _state.loadBrief,
                onReadMore: () => _showBrief(context),
                large: true,
                previewHeight: wide ? 470 : 300,
              );
=======
              final daily = personalBrief
                  ? _latestCard(context, top, wide)
                  : DailySummaryCard(
                      article: top,
                      large: true,
                      horizontal: !wide,
                      onTap: () => showArticleDialog(context, top),
                    );
              final brief = personalBrief
                  ? StorySummariesCard(
                      articles: _state.briefArticles,
                      loading: _state.briefLoading,
                      error: _state.briefError,
                      onRetry: _state.loadBrief,
                      onOpen: (a) => showArticleDialog(context, a),
                      large: true,
                      height: wide ? 560 : 380,
                    )
                  : WrittenSummaryCard(
                      sources: _state.briefArticles,
                      brief: _state.brief,
                      loading: _state.briefLoading,
                      error: _state.briefError,
                      onRetry: _state.loadBrief,
                      onReadMore: () => _showBrief(context),
                      large: true,
                      previewHeight: wide ? 470 : 300,
                    );
              final personal = _state.feedIsPersonal && !_state.feedIsFallback;
>>>>>>> ba5d700 (All system base developed for system design at backend server. Also Flutter Frontend developed.)
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 7, child: daily),
                        const SizedBox(width: 24),
                        Expanded(flex: 5, child: brief),
                      ],
                    )
                  else ...[
                    daily,
                    const SizedBox(height: 24),
                    brief,
                  ],
                  const SizedBox(height: 44),
                  SectionTitle(
<<<<<<< HEAD
                    'Trending',
                    trailing: LinkButton(
                      'See all',
                      onTap: () => _state.goTo(AppState.navDiscover),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _NewsGrid(
                    news: feed.skip(1).take(columns).toList(),
=======
                    personal ? 'Picked for you' : 'Trending',
                    trailing: personal
                        ? LinkButton(
                            'Open WOF Feed',
                            onTap: () => _state.goTo(AppState.navFeed),
                          )
                        : LinkButton(
                            'See all',
                            onTap: () => _state.goTo(AppState.navDiscover),
                          ),
                  ),
                  const SizedBox(height: 20),
                  _NewsGrid(
                    news: feed.skip(briefStories).take(columns).toList(),
>>>>>>> ba5d700 (All system base developed for system design at backend server. Also Flutter Frontend developed.)
                    columns: columns,
                  ),
                  const SizedBox(height: 44),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 7, child: _SavedPanel()),
                      SizedBox(width: 24),
                      Expanded(flex: 5, child: _StreakPanel()),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

<<<<<<< HEAD
  void _showBrief(BuildContext context) {
    final sources = _state.briefArticles;
=======
  /// "Latest developments": sunucunun en üstteki haberlerden yazdığı başlık
  /// ve paragraf. Yüklenirken ya da yazılamazsa en üstteki haber gösterilir.
  Widget _latestCard(BuildContext context, Article top, bool wide) {
    final headline = _state.briefTitle;
    final paragraph = _state.brief;
    final ready = headline != null && paragraph != null;
    final stories = _state.briefArticles;
    final lead = stories.firstOrNull ?? top;
    if (!ready && !_state.briefLoading) {
      return DailySummaryCard(
        article: top,
        large: true,
        horizontal: !wide,
        onTap: () => showArticleDialog(context, top),
      );
    }
    return DailySummaryCard(
      article: lead,
      large: true,
      horizontal: !wide,
      label: 'LATEST DEVELOPMENTS',
      title: ready ? headline : 'Catching you up…',
      summary: ready
          ? paragraph
          : 'WAI is reading the stories ranked highest for you.',
      summaryMaxLines: 7,
      caption: stories.isEmpty
          ? null
          : 'From ${stories.length} stories picked for you',
      onTap: ready ? () => _showBrief(context) : null,
      onAsk: ready ? _state.askLatest : null,
    );
  }

  void _showBrief(BuildContext context) {
    final sources = _state.briefArticles;
    final digest = _state.hasServerUser;
>>>>>>> ba5d700 (All system base developed for system design at backend server. Also Flutter Frontend developed.)
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) => Dialog(
        backgroundColor: AppColors.surface,
        insetPadding: const EdgeInsets.all(40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: const BorderSide(color: AppColors.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 860),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(36, 30, 36, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
<<<<<<< HEAD
                        'Cross-Source Brief',
=======
                        digest
                            ? (_state.briefTitle ?? 'Latest developments')
                            : 'Cross-Source Brief',
>>>>>>> ba5d700 (All system base developed for system design at backend server. Also Flutter Frontend developed.)
                        style: GoogleFonts.playfairDisplay(
                          color: AppColors.textPrimary,
                          fontSize: 30,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.iconMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
<<<<<<< HEAD
                  'WAI compared these stories for shared facts, '
                  'contradictions and unverified claims.',
=======
                  digest
                      ? 'WAI wrote this from the ${sources.length} stories '
                            'ranked highest for you. Each story\'s own '
                            'summary is in your Daily Brief.'
                      : 'WAI compared these stories for shared facts, '
                            'contradictions and unverified claims.',
>>>>>>> ba5d700 (All system base developed for system design at backend server. Also Flutter Frontend developed.)
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 16),
<<<<<<< HEAD
=======
                // Kişisel kartta önce paragraf, sonra kaynak haberler;
                // karşılaştırmalı özette önce karşılaştırılan haberler.
                if (digest) ...[
                  SimpleMarkdown(_state.brief ?? '', fontSize: 16.5),
                  const SizedBox(height: 16),
                  const Divider(color: AppColors.border),
                  const SizedBox(height: 16),
                ],
>>>>>>> ba5d700 (All system base developed for system design at backend server. Also Flutter Frontend developed.)
                for (final a in sources)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: NewsListTile(a, thumbSize: 48),
                  ),
<<<<<<< HEAD
                const SizedBox(height: 16),
                const Divider(color: AppColors.border),
                const SizedBox(height: 16),
                SimpleMarkdown(_state.brief ?? '', fontSize: 16.5),
=======
                if (!digest) ...[
                  const SizedBox(height: 16),
                  const Divider(color: AppColors.border),
                  const SizedBox(height: 16),
                  SimpleMarkdown(_state.brief ?? '', fontSize: 16.5),
                ],
>>>>>>> ba5d700 (All system base developed for system design at backend server. Also Flutter Frontend developed.)
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewsGrid extends StatelessWidget {
  const _NewsGrid({required this.news, required this.columns});

  final List<Article> news;
  final int columns;

  @override
  Widget build(BuildContext context) {
    const gap = 20.0;
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final n in news) SizedBox(width: w, child: NewsGridCard(n)),
          ],
        );
      },
    );
  }
}

class _SavedPanel extends StatefulWidget {
  const _SavedPanel();

  @override
  State<_SavedPanel> createState() => _SavedPanelState();
}

class _SavedPanelState extends State<_SavedPanel> {
  final _state = AppState.instance;

  @override
  void initState() {
    super.initState();
    // Önceki oturumda kaydedilen haberler önbellekte olmayabilir.
    _state.ensureArticles(_state.saved);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        final saved = _state.savedArticles.take(3).toList();
        return PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.bookmark_rounded,
                    size: 20,
                    color: AppColors.accentLight,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Your saved stories',
                    style: GoogleFonts.playfairDisplay(
                      color: AppColors.textPrimary,
                      fontSize: 21,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  LinkButton(
                    'View in profile',
                    onTap: () => _state.goTo(AppState.navProfile),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (saved.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No saved stories yet. Click the bookmark icon on any '
                    'story to add it here.',
                    style: GoogleFonts.inter(
                      color: AppColors.textMuted,
                      fontSize: 13.5,
                    ),
                  ),
                )
              else
                for (final n in saved)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: NewsListTile(n, thumbSize: 64),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _StreakPanel extends StatelessWidget {
  const _StreakPanel();

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _minutes = [18, 25, 12, 30, 22, 9, 16];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().weekday - 1;
    const maxMinutes = 30;
    return PanelCard(
      gradient: RadialGradient(
        center: const Alignment(0.9, -0.9),
        radius: 1.3,
        colors: [
          AppColors.accentDeep.withValues(alpha: 0.22),
          AppColors.surface,
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OverlineLabel('Reading streak', color: AppColors.mint),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '14',
                style: GoogleFonts.playfairDisplay(
                  color: AppColors.textPrimary,
                  fontSize: 52,
                  fontWeight: FontWeight.w500,
                  height: 1,
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'days in a row',
                  style: GoogleFonts.inter(
                    color: AppColors.textBody,
                    fontSize: 14,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.local_fire_department_rounded,
                color: AppColors.mint,
                size: 36,
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Tooltip(
                      message: '${_minutes[i]} min read',
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            width: 22,
                            height: 84 * _minutes[i] / maxMinutes,
                            decoration: BoxDecoration(
                              color: i == today
                                  ? AppColors.accentLight
                                  : AppColors.accent.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _days[i],
                            style: GoogleFonts.inter(
                              color: i == today
                                  ? AppColors.textPrimary
                                  : AppColors.textMuted,
                              fontSize: 12,
                              fontWeight: i == today
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'You read 2 h 12 min this week. 18 min left to reach your goal.',
            style: GoogleFonts.inter(
              color: AppColors.textBody,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
