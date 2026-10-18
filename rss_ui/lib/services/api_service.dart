import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/api_models.dart';

/// Intelligence RSS Platform istemcisi.
///
/// Flutter'a bağımlı değildir; `bin/` altındaki betikler `dart run` ile de
<<<<<<< HEAD
/// kullanabilir. Adres derleme sırasında verilir:
=======
/// kullanabilir. Varsayılan adres bu bilgisayarda çalışan yerel sunucudur;
/// tünel gibi başka bir adres derleme sırasında verilir:
>>>>>>> ba5d700 (All system base developed for system design at backend server. Also Flutter Frontend developed.)
///
///     flutter run -d chrome --dart-define=API_BASE_URL=https://xyz.loca.lt
class ApiService {
  ApiService({
    String baseUrl = defaultBaseUrl,
    http.Client? client,
    this.logger,
    this.timeout = const Duration(seconds: 30),
    this.slowTimeout = const Duration(seconds: 90),
<<<<<<< HEAD
=======
    this.digestTimeout = const Duration(seconds: 180),
>>>>>>> ba5d700 (All system base developed for system design at backend server. Also Flutter Frontend developed.)
  }) : baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _client = client ?? http.Client();

  static const defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
<<<<<<< HEAD
    defaultValue: 'https://tame-mails-march.loca.lt',
=======
    // "localhost" önce IPv6'yı dener; sunucu yalnızca IPv4'te dinliyor.
    defaultValue: 'http://127.0.0.1:8000',
>>>>>>> ba5d700 (All system base developed for system design at backend server. Also Flutter Frontend developed.)
  );

  /// Sunucudaki test kayıtları; akışta ve aramada gösterilmez.
  static const hiddenSources = {'Benchmark News'};

  /// Sunucunun `/api/search` için istediği en kısa sorgu.
  static const minSearchLength = 2;

  final String baseUrl;
  final http.Client _client;

  /// Doluysa her istek ve yanıt kodu buraya yazılır (ör. `debugPrint`).
  final void Function(String message)? logger;

  /// Hızlı uç noktalar (liste, detay, giriş, yorumlar).
  final Duration timeout;

  /// Yapay zeka kullanan uç noktalar (arama, chat, synthesize). İlk arama
  /// sunucuda model yüklendiği için ~45 sn sürebiliyor.
  final Duration slowTimeout;

<<<<<<< HEAD
=======
  /// Günün özeti: ilk üretimde Tavily doğrulaması + uzun model yanıtı.
  final Duration digestTimeout;

>>>>>>> ba5d700 (All system base developed for system design at backend server. Also Flutter Frontend developed.)
  Map<String, String> get _headers => const {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    // Localtunnel'in "uyarı sayfası"nı atlamak için.
    'bypass-tunnel-reminder': 'true',
  };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  // ==========================================================================
  // GET
  // ==========================================================================

  /// Haber akışının bir sayfası. [page] 1'den başlar. [macro] ile kategoriye
  /// göre süzer (ör. "Tech").
  ///
  /// Test kayıtları gizlendiği için bir sayfa boş gelse bile sonraki sayfa
  /// dolu olabilir; devam edip etmemeye [ArticlePage.hasMore] ile karar ver.
  Future<ArticlePage> getArticlePage({
    int page = 1,
    int pageSize = 20,
    String? macro,
  }) async {
    final size = pageSize.clamp(1, 100);
    final query = {
      'page': '${page < 1 ? 1 : page}',
      'page_size': '$size',
      if (macro != null && macro.isNotEmpty) 'macro': macro,
    };
    final raw = _list(await _getJson(_uri('/api/articles', query)));
    return ArticlePage(
      items: _visible(raw.map(Article.fromJson)),
      hasMore: raw.length >= size,
    );
  }

  /// [getArticlePage]'in yalnızca haberleri.
  Future<List<Article>> getArticles({
    int page = 1,
    int pageSize = 20,
    String? macro,
  }) async => (await getArticlePage(
    page: page,
    pageSize: pageSize,
    macro: macro,
  )).items;

  /// Tek haberin detayı (tam metin `cleanText` dahil).
  Future<Article> getArticle(String articleId) async {
    final json = await _getJson(_uri('/api/articles/${_id(articleId)}'));
    return Article.fromJson(_map(json));
  }

  /// Doğal dil araması; doğrudan eşleşmeler önce gelir.
  Future<List<SearchHit>> searchArticles(String query) async {
    final q = query.trim();
    if (q.length < minSearchLength) return const [];
    final json = await _getJson(
      _uri('/api/search', {'q': q}),
      timeout: slowTimeout,
    );
    return _list(json)
        .map(SearchHit.fromJson)
        .where((h) => !hiddenSources.contains(h.article.source))
        .toList();
  }

  /// Doğal dil araması; sonuçlar "doğrudan" ve "keşif" olarak ayrılır.
  Future<GroupedSearch> searchGrouped(String query) async {
    final q = query.trim();
    if (q.length < minSearchLength) return GroupedSearch.empty;
    final json = await _getJson(
      _uri('/api/search', {'q': q, 'grouped': 'true'}),
      timeout: slowTimeout,
    );
    final result = GroupedSearch.fromJson(_map(json));
    bool shown(SearchHit h) => !hiddenSources.contains(h.article.source);
    return GroupedSearch(
      query: result.query,
      direct: result.direct.where(shown).toList(),
      explore: result.explore.where(shown).toList(),
    );
  }

  /// Bir haberin yorumları (eskiden yeniye).
  Future<List<ArticleComment>> getComments(String articleId) async {
    final json = await _getJson(
      _uri('/api/articles/${_id(articleId)}/comments'),
    );
    return _list(json).map(ArticleComment.fromJson).toList();
  }

  /// Tüm kullanıcılar (yönetim/test amaçlı).
  Future<List<AppUser>> getUsers() async {
    final json = await _getJson(_uri('/api/users'));
    return _list(json).map(AppUser.fromJson).toList();
  }

  // ==========================================================================
<<<<<<< HEAD
=======
  // Kişiselleştirme
  // ==========================================================================

  /// Seçilebilecek kategoriler ve alt etiketleri. Liste sunucunun kodunda
  /// sabittir; veritabanına gitmediği için hızlı döner.
  Future<List<TaxonomyCategory>> getTaxonomy() async {
    final json = await _getJson(_uri('/api/taxonomy'));
    return _list(json).map(TaxonomyCategory.fromJson).toList();
  }

  /// Kullanıcının kayıtlı ilgi alanları.
  Future<AppUser> getPreferences(String userId) async {
    final json = await _getJson(_uri('/api/users/${_id(userId)}/preferences'));
    return AppUser.fromJson(_map(json));
  }

  /// İlgi alanlarını kaydeder ve onboarding'i tamamlar.
  ///
  /// Sunucu ilgi vektörünü `interestContext` cümlesinden (gerekirse
  /// İngilizceye çevirip), cümle yoksa seçimlerden kurduğu standart cümleden
  /// yeniden üretir; beğenilerden öğrenilen profil sıfırlanır.
  Future<PreferencesResult> updatePreferences(
    String userId, {
    required List<String> macroTags,
    List<String> microTags = const [],
    String? interestContext,
  }) async {
    if (macroTags.isEmpty) {
      throw const ApiException(
        ApiErrorKind.badRequest,
        'Pick at least one topic',
      );
    }
    final json = _map(
      await _send(
        'PUT',
        _uri('/api/users/${_id(userId)}/preferences'),
        body: {
          'preferred_macro_tags': macroTags,
          'preferred_micro_tags': microTags,
          // null: sunucudaki cümle kalır; '': silinir.
          if (interestContext != null) 'interest_context': interestContext,
        },
        timeout: slowTimeout,
      ),
    );
    return PreferencesResult(
      user: AppUser.fromJson(json),
      interestSummary: json['interest_summary'] as String?,
    );
  }

  /// "Neden" cümlesinin sunucunun kabul ettiği en fazla uzunluğu.
  static const maxContextChars = 200;

  /// Sunucunun kabul ettiği en fazla "+" takip sayısı.
  static const maxFollows = 3;

  /// Kullanıcının "+" ile takip ettikleri (eklenme sırasıyla).
  Future<List<UserFollow>> getFollows(String userId) async {
    final json = await _getJson(_uri('/api/users/${_id(userId)}/follows'));
    return _list(json).map(UserFollow.fromJson).toList();
  }

  /// Takip ekler. Sunucu aynı şeyi ilk kez takip edilince hemen bir kez
  /// çeker (1 Tavily kredisi), sonra 2 günde bir ortak sorguyla günceller.
  /// Zaten takip ediliyorsa mevcut kaydı döndürür.
  Future<UserFollow> addFollow(
    String userId, {
    required String name,
    required String macro,
  }) async {
    final json = await _postJson(_uri('/api/users/${_id(userId)}/follows'), {
      'name': name.trim(),
      'macro': macro,
    });
    return UserFollow.fromJson(_map(json));
  }

  Future<void> removeFollow(String userId, String followId) async {
    await _send(
      'DELETE',
      _uri('/api/users/${_id(userId)}/follows/${_id(followId)}'),
    );
  }

  /// Kişiye özel akışın bir sayfası; en uygun haber önce gelir.
  ///
  /// Kullanıcı ilgi alanı seçmediyse sunucu tarih sıralı akış döndürür
  /// ([PersonalizedFeed.isFallback]).
  Future<PersonalizedFeed> getPersonalizedFeed(
    String userId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final size = pageSize.clamp(1, 100);
    final json = _map(
      await _getJson(
        _uri('/api/feed/personalized', {
          'user_id': userId,
          'page': '${page < 1 ? 1 : page}',
          'page_size': '$size',
        }),
        timeout: slowTimeout,
      ),
    );
    final raw = json['articles'];
    final items = raw is List
        ? raw.whereType<Map<String, dynamic>>().toList()
        : const <Map<String, dynamic>>[];
    return PersonalizedFeed(
      articles: _visible(items.map(Article.fromJson)),
      hasMore: items.length >= size,
      isFallback: json['is_fallback'] == true,
    );
  }

  /// Beğeni / beğenmeme / kaydetme durumunu değiştirir.
  ///
  /// Sunucu bu uç noktayı aç/kapa olarak işler. Beğenide kullanıcının ilgi
  /// vektörü habere doğru kayar ve haberin kategorisi tercihlere eklenir;
  /// beğenmemede vektör haberden uzaklaşır ve haber akıştan çıkar.
  Future<InteractionResult> toggleInteraction(
    String articleId, {
    required String userId,
    required InteractionType type,
  }) async {
    final json = _map(
      await _postJson(_uri('/api/articles/${_id(articleId)}/interactions'), {
        'user_id': userId,
        'interaction_type': type.name,
      }),
    );
    return InteractionResult.fromJson(json);
  }

  /// Etkileşimi istenen duruma getirir. Sunucu aç/kapa çalıştığı için yanıt
  /// istenenden farklıysa bir kez daha gönderir.
  Future<InteractionResult> setInteraction(
    String articleId, {
    required String userId,
    required InteractionType type,
    required bool active,
  }) async {
    final result = await toggleInteraction(
      articleId,
      userId: userId,
      type: type,
    );
    if (result.active == active) return result;
    return toggleInteraction(articleId, userId: userId, type: type);
  }

  /// Kullanıcının ilk kategorisi için günün doğrulanmış özeti.
  ///
  /// Gün + kategori başına bir kez üretilir (Tavily + yapay zeka, ~1 dk);
  /// sonraki çağrılar önbellekten hızlı döner.
  Future<DailyDigest> getDailyDigest({String? userId, String? macro}) async {
    final json = await _getJson(
      _uri('/api/intelligence/daily-digest', {
        if (userId != null) 'user_id': userId,
        if (macro != null) 'macro': macro,
      }),
      timeout: digestTimeout,
    );
    return DailyDigest.fromJson(_map(json));
  }

  /// Ana sayfanın "Latest developments" kartı: başlık, paragraf ve kartın
  /// yazıldığı haberler. İlk üretim ~2 sn, sonra önbellekten anında döner.
  /// İlgi alanı seçilmemişse sunucu 409 döndürür.
  Future<LatestDevelopments> getLatestDevelopments(String userId) async {
    final json = await _getJson(
      _uri('/api/users/${_id(userId)}/latest-developments'),
      timeout: slowTimeout,
    );
    return LatestDevelopments.fromJson(_map(json));
  }

  // ==========================================================================
>>>>>>> ba5d700 (All system base developed for system design at backend server. Also Flutter Frontend developed.)
  // POST
  // ==========================================================================

  /// Kullanıcı adıyla hızlı giriş; kullanıcı yoksa sunucu oluşturur.
  Future<AppUser> login(String username, {String? name}) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty) {
      throw const ApiException(
        ApiErrorKind.badRequest,
        'Username cannot be empty',
      );
    }
    final json = await _postJson(_uri('/api/users/login'), {
      'username': trimmed,
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
    });
    return AppUser.fromJson(_map(json));
  }

  /// Habere yorum ekler. Sunucu yalnızca `id` ve `created_at` döndürdüğü
  /// için yorumun geri kalanı gönderilen değerlerle tamamlanır.
  Future<ArticleComment> postComment(
    String articleId, {
    required AppUser user,
    required String commentText,
    String? selectedText,
  }) async {
    final text = commentText.trim();
    if (text.isEmpty) {
      throw const ApiException(
        ApiErrorKind.badRequest,
        'Comment cannot be empty',
      );
    }
    final selected = selectedText?.trim();
    final json = await _postJson(
      _uri('/api/articles/${_id(articleId)}/comments'),
      {
        'user_id': user.id,
        'comment_text': text,
        if (selected != null && selected.isNotEmpty) 'selected_text': selected,
      },
    );
    final res = _map(json);
    return ArticleComment(
      id: res['id'] as String,
      comment: text,
      username: user.username,
      avatarUrl: user.avatarUrl,
      selectedText: selected,
      createdAt: DateTime.tryParse('${res['created_at']}'),
    );
  }

  /// WAI ile haber sohbeti; yanıt parça parça akar.
  ///
  /// Sunucu düz metin akıtır. Mobilde parçalar geldikçe, web'de (tarayıcı
  /// `http` istemcisi) yanıt tamamlanınca tek parça halinde gelir.
  /// Hiç metin gelmezse [ApiErrorKind.emptyResponse] fırlatılır.
  Stream<String> chatStream(
    String articleId, {
    required String question,
    List<ChatTurn> history = const [],
  }) {
    return _postTextStream(_uri('/api/articles/${_id(articleId)}/chat'), {
      'question': question.trim(),
      // Sunucu zaten son 4 turu kullanıyor; fazlasını göndermeye gerek yok.
      'history': [
        for (final t in history.skip(
          history.length > 4 ? history.length - 4 : 0,
        ))
          t.toJson(),
      ],
    });
  }

<<<<<<< HEAD
=======
  /// WAI sohbetini açar. [mode]: `story` (haberin tam metni), `latest`
  /// (ana sayfadaki son gelişmeler) ya da `area` (seçilen kategori ya da alt
  /// konunun son haberleri). WAI kapsamı okuyup ilk mesajı kendisi yazar.
  Future<WaiOpening> openWai({
    required String userId,
    required String mode,
    String? articleId,
    String? area,
  }) async {
    final json = await _send(
      'POST',
      _uri('/api/wai/open'),
      body: {
        'user_id': userId,
        'mode': mode,
        if (articleId != null) 'article_id': articleId,
        if (area != null) 'area': area,
      },
      timeout: slowTimeout,
    );
    return WaiOpening.fromJson(_map(json));
  }

  /// [openWai] ile açılan sohbette bir soru; yanıt [chatStream] gibi akar.
  /// [sourceIds]: sohbetin açıldığı haberler (numaralar sabit kalsın diye).
  Stream<String> waiChatStream({
    required String userId,
    required String mode,
    String? articleId,
    String? area,
    List<String> sourceIds = const [],
    required String question,
    List<ChatTurn> history = const [],
  }) {
    return _postTextStream(_uri('/api/wai/chat'), {
      'user_id': userId,
      'mode': mode,
      if (articleId != null) 'article_id': articleId,
      if (area != null) 'area': area,
      'source_ids': sourceIds,
      'question': question.trim(),
      // Sunucu son 6 turu kullanıyor (WAI'nin açılış mesajı dahil).
      'history': [
        for (final t in history.skip(
          history.length > 6 ? history.length - 6 : 0,
        ))
          t.toJson(),
      ],
    });
  }

>>>>>>> ba5d700 (All system base developed for system design at backend server. Also Flutter Frontend developed.)
  /// [chatStream]'in tamamlanmış yanıtı.
  Future<String> chatWithArticle(
    String articleId, {
    required String question,
    List<ChatTurn> history = const [],
  }) => chatStream(articleId, question: question, history: history).join();

  /// Birden fazla haberi karşılaştırır (ortak noktalar, çelişkiler,
  /// doğrulanmamış iddialar). Yanıt Markdown metnidir ve akar.
  Stream<String> synthesizeStream(List<String> articleIds) {
    if (articleIds.length < 2) {
      return Stream.error(
        const ApiException(
          ApiErrorKind.badRequest,
          'At least 2 articles are required',
        ),
      );
    }
    return _postTextStream(_uri('/api/intelligence/synthesize'), {
      'article_ids': articleIds.map(_id).toList(),
    });
  }

  /// [synthesizeStream]'in tamamlanmış yanıtı (Markdown).
  Future<String> synthesizeArticles(List<String> articleIds) =>
      synthesizeStream(articleIds).join();

  void dispose() => _client.close();

  // ==========================================================================
  // İç yardımcılar
  // ==========================================================================

  /// Yol parçasına konacak id'yi kodlar (boşluk, "/" vb. için).
  String _id(String id) => Uri.encodeComponent(id.trim());

  List<Article> _visible(Iterable<Article> articles) =>
      articles.where((a) => !hiddenSources.contains(a.source)).toList();

  Future<Object?> _getJson(Uri uri, {Duration? timeout}) =>
      _send('GET', uri, timeout: timeout);

  Future<Object?> _postJson(Uri uri, Object body) =>
      _send('POST', uri, body: body);

  Future<Object?> _send(
    String method,
    Uri uri, {
    Object? body,
    Duration? timeout,
  }) async {
    final sw = Stopwatch()..start();
    logger?.call('[$method] $uri');
    final http.Response res;
    try {
<<<<<<< HEAD
      final req = method == 'GET'
          ? _client.get(uri, headers: _headers)
          : _client.post(uri, headers: _headers, body: jsonEncode(body));
=======
      final req = switch (method) {
        'GET' => _client.get(uri, headers: _headers),
        'PUT' => _client.put(uri, headers: _headers, body: jsonEncode(body)),
        'DELETE' => _client.delete(uri, headers: _headers),
        _ => _client.post(uri, headers: _headers, body: jsonEncode(body)),
      };
>>>>>>> ba5d700 (All system base developed for system design at backend server. Also Flutter Frontend developed.)
      res = await req.timeout(timeout ?? this.timeout);
    } on TimeoutException {
      throw ApiException(ApiErrorKind.timeout, 'Request timed out: $uri');
    } on http.ClientException catch (e) {
      throw ApiException(ApiErrorKind.network, e.message);
    }
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    logger?.call('  └─ ${res.statusCode} (${sw.elapsedMilliseconds} ms)');
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException.fromResponse(res.statusCode, text);
    }
    try {
      return jsonDecode(text);
    } on FormatException {
      throw ApiException(
        ApiErrorKind.invalidResponse,
        'Expected JSON from $uri',
        statusCode: res.statusCode,
      );
    }
  }

  Stream<String> _postTextStream(Uri uri, Object body) async* {
    final sw = Stopwatch()..start();
    logger?.call('[POST/stream] $uri');
    final req = http.Request('POST', uri)
      ..headers.addAll(_headers)
      ..body = jsonEncode(body);

    final http.StreamedResponse res;
    try {
      res = await _client.send(req).timeout(slowTimeout);
    } on TimeoutException {
      throw ApiException(ApiErrorKind.timeout, 'Request timed out: $uri');
    } on http.ClientException catch (e) {
      throw ApiException(ApiErrorKind.network, e.message);
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final text = await res.stream.bytesToString().catchError((_) => '');
      logger?.call('  └─ ${res.statusCode} (${sw.elapsedMilliseconds} ms)');
      throw ApiException.fromResponse(res.statusCode, text);
    }

    final isSse = (res.headers['content-type'] ?? '').contains(
      'text/event-stream',
    );
    final text = res.stream.transform(utf8.decoder).timeout(slowTimeout);
    var received = false;
    try {
      await for (final chunk in isSse ? _sseTokens(text) : text) {
        if (chunk.isEmpty) continue;
        if (!received && chunk.trim().isEmpty) continue;
        received = true;
        yield chunk;
      }
    } on TimeoutException {
      throw ApiException(ApiErrorKind.timeout, 'Response stalled: $uri');
    } on http.ClientException catch (e) {
      throw ApiException(ApiErrorKind.network, e.message);
    }
    logger?.call(
      '  └─ ${res.statusCode} stream (${sw.elapsedMilliseconds} ms)',
    );

    // Sunucu yapay zeka hatasında 200 + boş gövde döndürebiliyor.
    if (!received) {
      throw ApiException(
        ApiErrorKind.emptyResponse,
        'Empty response from $uri',
        statusCode: res.statusCode,
      );
    }
  }

  /// SSE gövdesini metin parçalarına çevirir.
  ///
  /// Sunucu biçimi: `data: {"token": "..."}` olayları, sonunda
  /// `data: [DONE]`. `{"error": ...}` / `{"detail": ...}` içeren bir olay
  /// ya da `event: error` gelirse [ApiErrorKind.server] fırlatılır.
  static Stream<String> _sseTokens(Stream<String> text) async* {
    var buffer = '';
    var event = '';
    final data = <String>[];

    await for (final chunk in text) {
      buffer += chunk;
      var nl = buffer.indexOf('\n');
      while (nl != -1) {
        var line = buffer.substring(0, nl);
        buffer = buffer.substring(nl + 1);
        if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
        if (line.isEmpty) {
          // Boş satır: olay tamamlandı.
          final result = _sseEvent(event, data);
          event = '';
          data.clear();
          if (result == null) return; // [DONE]
          if (result.isNotEmpty) yield result;
        } else if (line.startsWith('data:')) {
          data.add(_sseValue(line.substring(5)));
        } else if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        }
        nl = buffer.indexOf('\n');
      }
    }
    if (buffer.startsWith('data:')) data.add(_sseValue(buffer.substring(5)));
    final result = _sseEvent(event, data);
    if (result != null && result.isNotEmpty) yield result;
  }

  static String _sseValue(String raw) =>
      raw.startsWith(' ') ? raw.substring(1) : raw;

  /// Tek SSE olayının metni; `[DONE]` için `null`.
  static String? _sseEvent(String event, List<String> data) {
    if (data.isEmpty) return '';
    final payload = data.join('\n');
    if (payload.trim() == '[DONE]') return null;
    Object? json;
    try {
      json = jsonDecode(payload);
    } on FormatException {
      json = null;
    }
    final error = json is Map ? (json['error'] ?? json['detail']) : null;
    if (event == 'error' || error != null) {
      throw ApiException(ApiErrorKind.server, '${error ?? payload}');
    }
    if (json is Map) {
      final token = json['token'] ?? json['content'] ?? json['text'];
      return token is String ? token : '';
    }
    return json is String ? json : payload;
  }

  static List<Map<String, dynamic>> _list(Object? json) {
    if (json is List) return json.whereType<Map<String, dynamic>>().toList();
    throw const ApiException(
      ApiErrorKind.invalidResponse,
      'Expected a JSON list',
    );
  }

  static Map<String, dynamic> _map(Object? json) {
    if (json is Map<String, dynamic>) return json;
    throw const ApiException(
      ApiErrorKind.invalidResponse,
      'Expected a JSON object',
    );
  }
}

enum ApiErrorKind {
  /// İnternet yok, DNS/CORS hatası vb.
  network,

  /// Süre aşımı.
  timeout,

  /// Tünel kapalı ya da sunucu yanıt vermiyor (502/503/504).
  unavailable,

  /// 404.
  notFound,

  /// 400/422: istek hatalı.
  badRequest,

  /// Diğer 5xx hataları.
  server,

  /// 200 döndü ama içerik boş (chat/synthesize).
  emptyResponse,

  /// Yanıt beklenen biçimde değil.
  invalidResponse,
}

class ApiException implements Exception {
  const ApiException(this.kind, this.message, {this.statusCode});

  factory ApiException.fromResponse(int statusCode, String body) {
    final kind = switch (statusCode) {
      404 => ApiErrorKind.notFound,
      400 || 422 => ApiErrorKind.badRequest,
      502 || 503 || 504 => ApiErrorKind.unavailable,
      >= 500 => ApiErrorKind.server,
      _ => ApiErrorKind.badRequest,
    };
    return ApiException(kind, _detail(body), statusCode: statusCode);
  }

  final ApiErrorKind kind;

  /// Geliştirici için ayrıntı (sunucunun `detail` alanı vb.).
  final String message;
  final int? statusCode;

  /// Arayüzde gösterilecek İngilizce mesaj.
  String get userMessage => switch (kind) {
    ApiErrorKind.network || ApiErrorKind.unavailable =>
      'Server unavailable. Please try again in a moment.',
    ApiErrorKind.timeout => 'The server is taking too long to respond.',
    ApiErrorKind.notFound => 'This content could not be found.',
    ApiErrorKind.badRequest => message,
    ApiErrorKind.server ||
    ApiErrorKind.emptyResponse ||
    ApiErrorKind.invalidResponse => 'Something went wrong. Please try again.',
  };

  static String _detail(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map && json['detail'] != null) {
        final detail = json['detail'];
        // FastAPI doğrulama hataları: [{"msg": "...", ...}]
        if (detail is List && detail.isNotEmpty && detail.first is Map) {
          return '${(detail.first as Map)['msg']}';
        }
        return '$detail';
      }
    } on FormatException {
      // Düz metin gövde (ör. "503 - Tunnel Unavailable").
    }
    final trimmed = body.trim();
    return trimmed.length > 200 ? '${trimmed.substring(0, 200)}…' : trimmed;
  }

  @override
  String toString() =>
      'ApiException(${kind.name}${statusCode != null ? ', $statusCode' : ''}): $message';
}
