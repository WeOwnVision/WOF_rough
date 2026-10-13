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
  });

  factory Article.fromJson(Map<String, dynamic> json) {
    final macroTag = json['macro_tag'] as String?;
    final macroTags = _stringList(json['macro_tags']);
    return Article(
      id: json['id'] as String,
      source: (json['source'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
      author: json['author'] as String?,
      publishedAt: _date(json['published_at']),
      macroTag: macroTag,
      macroTags: macroTags.isEmpty && macroTag != null ? [macroTag] : macroTags,
      microTags: _stringList(json['micro_tags']),
      tldr: json['tldr'] as String?,
      cleanText: json['clean_text'] as String?,
    );
  }

  final String id;
  final String source;
  final String title;
  final String url;
  final String? author;
  final DateTime? publishedAt;

  /// Birincil kategori (Tech, AI, Hardware, Automotive, Gaming, Finance,
  /// Science). İşlenmemiş haberlerde boş olabilir.
  final String? macroTag;
  final List<String> macroTags;
  final List<String> microTags;
  final String? tldr;

  /// Haberin tam metni; yalnızca `getArticle` yanıtında gelir.
  final String? cleanText;

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
  };
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

/// `/api/users/login` ve `/api/users` öğesi.
class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    this.avatarUrl,
    this.createdAt,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    username: (json['username'] as String?) ?? '',
    avatarUrl: json['avatar_url'] as String?,
    createdAt: _date(json['created_at']),
  );

  final String id;
  final String username;
  final String? avatarUrl;
  final DateTime? createdAt;
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
