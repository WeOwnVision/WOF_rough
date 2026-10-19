/// Sunucudan (Intelligence RSS Platform) gelen JSON'ların modelleri.
///
/// Alan adları sunucunun `/openapi.json` şemasındaki yanıtlarla birebir
/// eşleşir. Sunucu bazı alanları `null` gönderebildiği için listeler boş
/// listeye, metinler `null`a düşürülür.
library;

List<String> _stringList(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// `/api/articles`, `/api/articles/{id}` ve `/api/search` öğeleri.
class Article {
  const Article({
    required this.id,
    required this.source,
    required this.title,
    required this.url,
    this.author,
    this.publishedAt,
    this.macroTag,
    this.macroTags = const [],
    this.microTags = const [],
    this.tldr,
    this.cleanText,
    this.personalScore,
    this.isLiked,
    this.matchedFollows = const [],
    this.imageUrl,
    this.imageStatus,
    this.factCheckCache,
  });

  factory Article.fromJson(Map<String, dynamic> json) {
    final macroTag = json['macro_tag'] as String?;
    final macroTags = _stringList(json['macro_tags']);
    return Article(
      id: json['id'] as String,
      source: (json['source'] as String?) ?? (json['source_feed'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      url: (json['url'] as String?) ?? (json['link'] as String?) ?? '',
      author: json['author'] as String?,
      publishedAt: _date(json['published_at']),
      macroTag: macroTag,
      macroTags: macroTags.isEmpty && macroTag != null ? [macroTag] : macroTags,
      microTags: _stringList(json['micro_tags']),
      tldr: json['tldr'] as String?,
      cleanText: json['clean_text'] as String?,
      personalScore: (json['personal_score'] as num?)?.toInt(),
      isLiked: json['is_liked'] as bool?,
      matchedFollows: _stringList(json['matched_follows']),
      imageUrl: json['image_url'] as String?,
      imageStatus: json['image_status'] as String?,
      factCheckCache: json['fact_check_cache'] is Map<String, dynamic>
          ? FactCheckResult.fromJson(json['fact_check_cache'] as Map<String, dynamic>)
          : (json['fact_check_cache'] is Map
              ? FactCheckResult.fromJson(Map<String, dynamic>.from(json['fact_check_cache'] as Map))
              : null),
    );
  }

  final String id;
  final String source;
  final String title;
  final String url;
  final String? author;
  final DateTime? publishedAt;

  /// Birincil kategori (Tech, AI & Compute, Systems & Cloud, etc.).
  final String? macroTag;
  final List<String> macroTags;
  final List<String> microTags;
  final String? tldr;

  /// Haberin tam metni; yalnızca `getArticle` yanıtında gelir.
  final String? cleanText;

  /// Kişisel akıştaki uygunluk puanı (0-100).
  final int? personalScore;

  /// Kullanıcı bu haberi sunucuda beğenmiş mi.
  final bool? isLiked;

  /// Haberde adı geçen, kullanıcının "+" ile takip ettiği şeyler.
  final List<String> matchedFollows;

  /// 4-Aşamalı görsel çözücüden gelen görsel linki ve durumu.
  final String? imageUrl;
  final String? imageStatus;

  /// Tavily & Nemotron derin doğrulama / olgu kontrolü önbelleği.
  final FactCheckResult? factCheckCache;

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source,
    'title': title,
    'url': url,
    if (author != null) 'author': author,
    if (publishedAt != null) 'published_at': publishedAt!.toIso8601String(),
    if (macroTag != null) 'macro_tag': macroTag,
    'macro_tags': macroTags,
    'micro_tags': microTags,
    if (tldr != null) 'tldr': tldr,
    if (cleanText != null) 'clean_text': cleanText,
    if (personalScore != null) 'personal_score': personalScore,
    if (isLiked != null) 'is_liked': isLiked,
    if (matchedFollows.isNotEmpty) 'matched_follows': matchedFollows,
    if (imageUrl != null) 'image_url': imageUrl,
    if (imageStatus != null) 'image_status': imageStatus,
  };
}

class ClaimItem {
  const ClaimItem({
    required this.claim,
    required this.status,
    required this.evidenceSummary,
    this.sourceUrl,
  });

  factory ClaimItem.fromJson(Map<String, dynamic> json) {
    return ClaimItem(
      claim: (json['claim'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'unverified',
      evidenceSummary: (json['evidence_summary'] as String?) ?? '',
      sourceUrl: json['source_url'] as String?,
    );
  }

  final String claim;
  final String status;
  final String evidenceSummary;
  final String? sourceUrl;
}

class FactCheckResult {
  const FactCheckResult({
    required this.executiveSynthesis,
    required this.factCheckVerdict,
    this.claimMatrix = const [],
    this.biasAndNuance = '',
    this.isCached = false,
    this.limitedSource = false,
    this.modelUsed = '',
    this.sourcesConsulted = const [],
  });

  factory FactCheckResult.fromJson(Map<String, dynamic> json) {
    final claims = json['claim_matrix'];
    final sources = json['sources_consulted'];
    return FactCheckResult(
      executiveSynthesis: (json['executive_synthesis'] as String?) ?? '',
      factCheckVerdict: (json['fact_check_verdict'] as String?) ?? 'Unverified',
      claimMatrix: claims is List
          ? claims.whereType<Map<String, dynamic>>().map(ClaimItem.fromJson).toList()
          : const [],
      biasAndNuance: (json['bias_and_nuance'] as String?) ?? '',
      isCached: json['is_cached'] == true,
      limitedSource: json['limited_source'] == true,
      modelUsed: (json['model_used'] as String?) ?? '',
      sourcesConsulted: sources is List
          ? sources.whereType<Map<String, dynamic>>().map((s) => Map<String, String>.from(s.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')))).toList()
          : const [],
    );
  }

  final String executiveSynthesis;
  final String factCheckVerdict;
  final List<ClaimItem> claimMatrix;
  final String biasAndNuance;
  final bool isCached;
  final bool limitedSource;
  final String modelUsed;
  final List<Map<String, String>> sourcesConsulted;
}

class DeepInspectEvent {
  const DeepInspectEvent({required this.event, required this.data});
  final String event;
  final String data;
}

/// Arama sonucu: haber + sunucunun eşleşme bilgileri.
class SearchHit {
  const SearchHit({
    required this.article,
    required this.isDirect,
    this.relevanceScore,
    this.possibility,
    this.exploreAngle,
  });

  factory SearchHit.fromJson(Map<String, dynamic> json) => SearchHit(
    article: Article.fromJson(json),
    isDirect: json['match_tier'] != 'explore',
    relevanceScore: (json['relevance_score'] as num?)?.toInt(),
    possibility: json['possibility'] as String?,
    exploreAngle: json['explore_angle'] as String?,
  );

  final Article article;

  /// `match_tier == "direct"`; değilse "keşfetmek isteyebileceklerin".
  final bool isDirect;

  /// 0-99 arası ilgi puanı.
  final int? relevanceScore;

  /// "Direct Focus" / "Adjacent Horizon".
  final String? possibility;

  /// Keşif sonuçları için sunucunun ürettiği açı (ör. "Compute & ...").
  final String? exploreAngle;
}

/// `/api/search?grouped=true` yanıtı.
class GroupedSearch {
  const GroupedSearch({
    required this.query,
    required this.direct,
    required this.explore,
  });

  factory GroupedSearch.fromJson(Map<String, dynamic> json) {
    List<SearchHit> hits(Object? value) => value is List
        ? value
              .whereType<Map<String, dynamic>>()
              .map(SearchHit.fromJson)
              .toList()
        : const [];
    return GroupedSearch(
      query: (json['query'] as String?) ?? '',
      direct: hits(json['direct']),
      explore: hits(json['explore']),
    );
  }

  static const empty = GroupedSearch(query: '', direct: [], explore: []);

  final String query;
  final List<SearchHit> direct;
  final List<SearchHit> explore;

  bool get isEmpty => direct.isEmpty && explore.isEmpty;
}

/// `/api/articles/{id}/comments` öğesi.
class ArticleComment {
  const ArticleComment({
    required this.id,
    required this.comment,
    required this.username,
    this.selectedText,
    this.avatarUrl,
    this.createdAt,
  });

  factory ArticleComment.fromJson(Map<String, dynamic> json) => ArticleComment(
    id: json['id'] as String,
    // Sunucu GET'te `comment`, POST gövdesinde `comment_text` kullanıyor.
    comment: (json['comment'] ?? json['comment_text'] ?? '') as String,
    username: (json['username'] as String?) ?? '',
    selectedText: json['selected_text'] as String?,
    avatarUrl: json['avatar_url'] as String?,
    createdAt: _date(json['created_at']),
  );

  final String id;
  final String comment;
  final String username;

  /// Yorumun bağlandığı, haberden seçilmiş metin.
  final String? selectedText;
  final String? avatarUrl;
  final DateTime? createdAt;
}

/// `/api/users/login`, `/api/users` ve `/api/users/{id}/preferences` öğesi.
class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    this.avatarUrl,
    this.createdAt,
    this.onboardingCompleted = false,
    this.preferredMacroTags = const [],
    this.preferredMicroTags = const [],
    this.interestContext,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    username: (json['username'] as String?) ?? '',
    avatarUrl: json['avatar_url'] as String?,
    createdAt: _date(json['created_at']),
    onboardingCompleted: json['onboarding_completed'] == true,
    preferredMacroTags: _stringList(json['preferred_macro_tags']),
    preferredMicroTags: _stringList(json['preferred_micro_tags']),
    interestContext: json['interest_context'] as String?,
  );

  final String id;
  final String username;
  final String? avatarUrl;
  final DateTime? createdAt;

  /// İlgi alanlarını seçti mi? `false` ise onboarding ekranı açılır.
  final bool onboardingCompleted;

  /// Seçilen ana kategoriler (taksonomideki `macro` değerleri).
  final List<String> preferredMacroTags;

  /// Seçilen alt etiketler (taksonomideki `tag` değerleri).
  final List<String> preferredMicroTags;

  /// Onboarding'deki isteğe bağlı "neden" cümlesi, yazıldığı dilde
  /// (ör. "I invest"). Sunucu ilgi vektörünü bunun İngilizcesinden kurar;
  /// `null` ise seçilen konulardan kurulan standart cümleden.
  final String? interestContext;

  AppUser copyWith({
    String? avatarUrl,
    bool? onboardingCompleted,
    List<String>? preferredMacroTags,
    List<String>? preferredMicroTags,
  }) => AppUser(
    id: id,
    username: username,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    createdAt: createdAt,
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    preferredMacroTags: preferredMacroTags ?? this.preferredMacroTags,
    preferredMicroTags: preferredMicroTags ?? this.preferredMicroTags,
    interestContext: interestContext,
  );
}

/// `/api/taxonomy` içindeki bir alt etiket.
class TaxonomyTag {
  const TaxonomyTag({required this.tag, required this.label});

  factory TaxonomyTag.fromJson(Map<String, dynamic> json) => TaxonomyTag(
    tag: json['tag'] as String,
    label: (json['label'] as String?) ?? json['tag'] as String,
  );

  /// Sunucuya gönderilen değer (ör. `llm_agents`).
  final String tag;

  /// Arayüzde gösterilen ad (ör. "LLM Agents").
  final String label;
}

/// `/api/taxonomy` öğesi: bir ana kategori ve alt etiketleri.
///
/// Liste sunucunun kodunda sabittir; kullanıcı seçimleri bunu değiştirmez.
class TaxonomyCategory {
  const TaxonomyCategory({
    required this.macro,
    required this.displayName,
    this.description = '',
    this.microTags = const [],
  });

  factory TaxonomyCategory.fromJson(Map<String, dynamic> json) {
    final macro = json['macro'] as String;
    final tags = json['micro_tags'];
    return TaxonomyCategory(
      macro: macro,
      displayName: (json['display_name'] as String?) ?? macro,
      description: (json['description'] as String?) ?? '',
      microTags: tags is List
          ? tags
                .whereType<Map<String, dynamic>>()
                .map(TaxonomyTag.fromJson)
                .toList()
          : const [],
    );
  }

  /// Sunucuya gönderilen değer (ör. `AI`).
  final String macro;
  final String displayName;
  final String description;
  final List<TaxonomyTag> microTags;
}

/// "+" ile takip edilen belirli bir şey (şirket, ürün, kişi), ör. "Revolut".
///
/// Sunucuda aynı şeyi takip eden herkes için tek bir arama sorgusu çalışır;
/// akışta adı geçen haberler öne çıkar.
class UserFollow {
  const UserFollow({required this.name, required this.macro, this.id});

  factory UserFollow.fromJson(Map<String, dynamic> json) => UserFollow(
    id: json['id'] as String?,
    name: (json['name'] as String?) ?? '',
    macro: (json['macro'] as String?) ?? '',
  );

  /// Sunucudaki kayıt kimliği; henüz kaydedilmemişse `null`.
  final String? id;
  final String name;

  /// Bağlı olduğu kategori (sorguya bağlam katar: "Revolut finance").
  final String macro;

  /// Büyük/küçük harf ve boşluk farkı gözetmeyen anahtar (sunucuyla aynı).
  String get key => name.trim().split(RegExp(r'\s+')).join(' ').toLowerCase();
}

/// `PUT /api/users/{id}/preferences` yanıtı.
class PreferencesResult {
  const PreferencesResult({required this.user, this.interestSummary});

  final AppUser user;

  /// Sunucunun seçimlerden kurduğu ve ilgi vektörüne çevirdiği cümle.
  final String? interestSummary;
}

/// `/api/feed/personalized` yanıtı.
class PersonalizedFeed {
  const PersonalizedFeed({
    required this.articles,
    required this.hasMore,
    this.isFallback = false,
  });

  final List<Article> articles;

  /// Sunucu tam sayfa döndürdüyse sonraki sayfa da olabilir.
  final bool hasMore;

  /// `true`: kullanıcı ilgi alanı seçmemiş, akış tarih sıralı geliyor.
  final bool isFallback;
}

/// `POST /api/articles/{id}/interactions` için etkileşim türleri.
///
/// [like] ve [dislike] sunucuda birbirini dışlar: biri kaydedilince diğeri
/// silinir. [dislike] haberi kişisel akıştan çıkarır.
enum InteractionType { like, dislike, bookmark }

/// `POST /api/articles/{id}/interactions` yanıtı.
class InteractionResult {
  const InteractionResult({
    required this.active,
    this.preferredMacroTags,
    this.preferredMicroTags,
  });

  factory InteractionResult.fromJson(Map<String, dynamic> json) {
    List<String>? tags(Object? v) => v is List ? _stringList(v) : null;
    return InteractionResult(
      active: json['active'] == true,
      preferredMacroTags: tags(json['updated_preferred_macro_tags']),
      preferredMicroTags: tags(json['updated_preferred_micro_tags']),
    );
  }

  /// Etkileşim kayıtlı mı (`false`: sunucu aç/kapa ile sildi).
  final bool active;

  /// Beğeni / beğenmeme sonrası sunucunun güncellediği tercihler. Beğenilen
  /// haberin kategorisi ve etiketleri eklenir; kayıt silindiyse `null`.
  final List<String>? preferredMacroTags;
  final List<String>? preferredMicroTags;
}

/// `/api/intelligence/daily-digest` yanıtı.
class DailyDigest {
  const DailyDigest({
    required this.macroTag,
    required this.clusterTitle,
    required this.report,
    this.articles = const [],
    this.isCached = false,
  });

  factory DailyDigest.fromJson(Map<String, dynamic> json) {
    final arts = json['articles'];
    return DailyDigest(
      macroTag: (json['macro_tag'] as String?) ?? '',
      clusterTitle: (json['cluster_title'] as String?) ?? '',
      report: (json['synthesis_report'] as String?) ?? '',
      articles: arts is List
          ? arts
                .whereType<Map<String, dynamic>>()
                .where((a) => a['id'] is String)
                .map(Article.fromJson)
                .toList()
          : const [],
      isCached: json['is_cached'] == true,
    );
  }

  /// Özetin konusu olan kategori (kullanıcının ilk seçtiği).
  final String macroTag;
  final String clusterTitle;

  /// Markdown rapor.
  final String report;

  /// Raporda karşılaştırılan haberler.
  final List<Article> articles;
  final bool isCached;
}

/// `GET /api/users/{id}/latest-developments`: ana sayfadaki "Latest
/// developments" kartı. Sunucu kullanıcının en üstteki haberlerinden bir
/// başlık ve paragraf yazar ve kullanıcı başına saklar.
class LatestDevelopments {
  const LatestDevelopments({
    required this.headline,
    required this.paragraph,
    this.articles = const [],
    this.refreshing = false,
  });

  factory LatestDevelopments.fromJson(Map<String, dynamic> json) {
    final arts = json['articles'];
    return LatestDevelopments(
      headline: (json['headline'] as String?) ?? '',
      paragraph: (json['paragraph'] as String?) ?? '',
      articles: arts is List
          ? arts
                .whereType<Map<String, dynamic>>()
                .where((a) => a['id'] is String)
                .map(Article.fromJson)
                .toList()
          : const [],
      refreshing: json['refreshing'] == true,
    );
  }

  /// Kısa başlık (sunucu en fazla 70 karakterle sınırlar).
  final String headline;

  /// Son gelişmelerin 3-4 cümlelik paragrafı.
  final String paragraph;

  /// Kartın yazıldığı haberler, akıştaki sırayla.
  final List<Article> articles;

  /// Sunucu kartı arka planda yeniliyor; biraz sonra tekrar istenebilir.
  final bool refreshing;
}

/// `POST /api/wai/open`: WAI'nin açtığı sohbet. Sunucu kapsamı (haber, son
/// gelişmeler ya da alan) okur ve ilk mesajı kendisi yazar.
class WaiOpening {
  const WaiOpening({
    required this.title,
    required this.opening,
    this.subtitle = '',
    this.sources = const [],
  });

  factory WaiOpening.fromJson(Map<String, dynamic> json) {
    final arts = json['sources'];
    return WaiOpening(
      title: (json['title'] as String?) ?? '',
      subtitle: (json['subtitle'] as String?) ?? '',
      opening: (json['opening'] as String?) ?? '',
      sources: arts is List
          ? arts
                .whereType<Map<String, dynamic>>()
                .where((a) => a['id'] is String)
                .map(Article.fromJson)
                .toList()
          : const [],
    );
  }

  /// Haber başlığı, son gelişmeler başlığı ya da alan adı.
  final String title;

  /// Ör. "Your latest developments · 8 stories".
  final String subtitle;

  /// WAI'nin ilk mesajı.
  final String opening;

  /// WAI'nin okuduğu haberler; cevaplardaki [1], [2] bu sıraya karşılık gelir.
  final List<Article> sources;
}

/// WAI sohbet geçmişindeki bir tur.
class ChatTurn {
  const ChatTurn.user(this.content) : role = 'user';
  const ChatTurn.assistant(this.content) : role = 'assistant';

  final String role;
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};
}

/// `/api/articles` sayfası.
class ArticlePage {
  const ArticlePage({required this.items, required this.hasMore});

  final List<Article> items;

  /// Sunucu tam sayfa döndürdüyse sonraki sayfa da olabilir.
  final bool hasMore;
}
