import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rss_ui/screens/home_page.dart';
import 'package:rss_ui/services/api_service.dart';
import 'package:rss_ui/state/app_state.dart';
import 'package:rss_ui/web/web_gate.dart';
import 'package:rss_ui/web/web_shell.dart';

Map<String, Object?> _article(int i) => {
  'id': 'id-$i',
  'source': 'Source $i',
  'title': 'Story number $i about chips',
  'url': 'https://example.com/$i',
  'author': 'Author $i',
  'published_at': '2026-10-09T1$i:00:00+00:00',
  'macro_tag': 'Tech',
  'macro_tags': ['Tech', 'Hardware'],
  'micro_tags': ['semiconductors', 'gpu'],
  'tldr': 'Short summary of story $i.',
};

String _sse(List<String> tokens) => [
  for (final t in tokens) 'data: ${jsonEncode({'token': t})}\n\n',
  'data: [DONE]\n\n',
].join();

const _taxonomy = [
  {
    'macro': 'AI',
    'display_name': 'Artificial Intelligence',
    'description': 'Large language models, autonomous agents',
    'micro_tags': [
      {'tag': 'llm_agents', 'label': 'LLM Agents'},
      {'tag': 'nvidia', 'label': 'NVIDIA'},
    ],
  },
  {
    'macro': 'Gaming',
    'display_name': 'Gaming & Handhelds',
    'description': 'Video games, consoles, Steam Deck',
    'micro_tags': [
      {'tag': 'steam_deck', 'label': 'Steam Deck'},
    ],
  },
];

/// Sahte sunucuya gelen istekler (yöntem + yol + gövde).
final _requests = <http.Request>[];

/// Sunucuyu taklit eden istemci. [chatReply] boşsa chat boş akış döndürür.
/// [onboarded] `false` ise giriş yapan kullanıcı ilgi alanı seçmemiştir.
MockClient _server({
  String chatReply = 'It is about faster chips.',
  bool onboarded = true,
}) {
  var macros = onboarded ? ['AI'] : <String>[];
  var micros = onboarded ? ['llm_agents'] : <String>[];
  String? why = onboarded ? 'I build products' : null;
  // Sunucudaki etkileşimler: "id-0:like", "id-1:dislike", ...
  final interactions = <String>{};
  bool has(String id, String type) => interactions.contains('$id:$type');
  // "+" takipler; id-3 takip edilen şeyden bahseden haber.
  final follows = <Map<String, Object?>>[];
  return MockClient((req) async {
    _requests.add(req);
    final path = req.url.path;
    http.Response json(Object body) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: {'content-type': 'application/json'},
    );
    http.Response sse(String body) => http.Response.bytes(
      utf8.encode(body),
      200,
      headers: {'content-type': 'text/event-stream; charset=utf-8'},
    );

    if (path == '/api/articles') {
      final page = int.parse(req.url.queryParameters['page'] ?? '1');
      return json(page == 1 ? [for (var i = 0; i < 6; i++) _article(i)] : []);
    }
    if (path == '/api/search') {
      final q = req.url.queryParameters['q'];
      return json({
        'query': q,
        'direct': [
          {..._article(1), 'match_tier': 'direct', 'relevance_score': 95},
        ],
        'explore': [
          {
            ..._article(2),
            'match_tier': 'explore',
            'relevance_score': 60,
            'explore_angle': 'Compute & Acceleration',
          },
        ],
      });
    }
    Map<String, Object?> user([String username = 'can_test']) => {
      'id': 'u1',
      'username': username,
      'avatar_url': null,
      'onboarding_completed': macros.isNotEmpty,
      'preferred_macro_tags': macros,
      'preferred_micro_tags': micros,
      'interest_context': why,
    };

    if (path == '/api/users/login') {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      return json(user(body['username'] as String));
    }
    if (path == '/api/taxonomy') return json(_taxonomy);
    if (path.startsWith('/api/users/u1/follows')) {
      if (req.method == 'POST') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final created = {
          'id': 'f${follows.length + 1}',
          'name': body['name'],
          'macro': body['macro'],
        };
        follows.add(created);
        return json(created);
      }
      if (req.method == 'DELETE') {
        follows.removeWhere((f) => path.endsWith('/${f['id']}'));
        return json({'status': 'removed'});
      }
      return json(follows);
    }
    if (path == '/api/users/u1/preferences') {
      if (req.method == 'PUT') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        macros = List<String>.from(body['preferred_macro_tags'] as List);
        micros = List<String>.from(body['preferred_micro_tags'] as List);
        if (body.containsKey('interest_context')) {
          final text = body['interest_context'] as String;
          why = text.isEmpty ? null : text;
        }
        return json({
          ...user(),
          'interest_summary': 'Technical news and updates in Ai.',
        });
      }
      return json(user());
    }
    if (path == '/api/feed/personalized') {
      final page = int.parse(req.url.queryParameters['page'] ?? '1');
      return json({
        'user_id': 'u1',
        'is_fallback': macros.isEmpty,
        'articles': page == 1
            ? [
                for (var i = 0; i < 6; i++)
                  // Beğenilmeyen haberler akıştan çıkar.
                  if (!has('id-$i', 'dislike'))
                    {
                      ..._article(i),
                      'personal_score': 90 - i,
                      'is_liked': has('id-$i', 'like'),
                      'is_disliked': false,
                      if (i == 3 && follows.isNotEmpty)
                        'matched_follows': [follows.first['name']],
                    },
              ]
            : [],
      });
    }
    if (path == '/api/users/u1/latest-developments') {
      if (macros.isEmpty) {
        return http.Response(
          jsonEncode({'detail': 'Pick your interests first'}),
          409,
        );
      }
      return json({
        'headline': 'Chipmakers race ahead as AI demand grows',
        'paragraph':
            'Story three and story four point the same way. '
            'Demand for AI chips keeps rising.',
        'articles': [_article(3), _article(4)],
        'model': 'deepseek-ai/DeepSeek-V4-Flash-0731',
        'refreshing': false,
      });
    }
    if (path == '/api/intelligence/daily-digest') {
      return json({
        'date': '2026-10-17',
        'macro_tag': macros.isEmpty ? 'Gaming' : macros.first,
        'cluster_title': 'Brief',
        'article_ids': ['id-1'],
        'articles': [_article(1)],
        'tavily_sources': [],
        'synthesis_report': '**1. Shared Consensus**\n- Verified.',
        'is_cached': false,
      });
    }
    if (path.endsWith('/interactions')) {
      // Sunucunun davranışı: aç/kapa; like ve dislike birbirini siler;
      // like haberin kategorisini ve ilk iki etiketini tercihlere ekler.
      final id = path.split('/')[3];
      final type =
          (jsonDecode(req.body) as Map<String, dynamic>)['interaction_type']
              as String;
      if (interactions.remove('$id:$type')) {
        return json({'status': 'removed', 'active': false});
      }
      if (type == 'like') interactions.remove('$id:dislike');
      if (type == 'dislike') interactions.remove('$id:like');
      interactions.add('$id:$type');
      if (type == 'like') {
        if (!macros.contains('Tech')) macros = [...macros, 'Tech'];
        micros = {'semiconductors', 'gpu', ...micros}.toList();
      }
      final learns = type == 'like' || type == 'dislike';
      return json({
        'status': 'recorded',
        'active': true,
        'updated_preferred_macro_tags': learns ? macros : null,
        'updated_preferred_micro_tags': learns ? micros : null,
      });
    }
    if (path == '/api/intelligence/synthesize') {
      return sse(_sse(['**1. Shared Consensus**\n', '- Chips are faster.']));
    }
    if (path == '/api/wai/open') {
      final mode = (jsonDecode(req.body) as Map<String, dynamic>)['mode'];
      return json({
        'mode': mode,
        'title': switch (mode) {
          'latest' => 'Chipmakers race ahead as AI demand grows',
          'area' => 'Artificial Intelligence',
          _ => 'Story number 0 about chips',
        },
        'subtitle': mode == 'story' ? 'Story chat' : '2 stories',
        'opening': mode == 'story'
            ? 'This story is about faster chips. Want the key points?'
            : "I've gone through the latest stories. Would you like me to "
                  'summarize the most striking aspects?',
        'sources': mode == 'story' ? [_article(0)] : [_article(3), _article(4)],
      });
    }
    if (path == '/api/wai/chat') {
      return sse(_sse(['Chip demand ', 'keeps rising [1].']));
    }
    if (path.endsWith('/chat')) {
      return sse(chatReply.isEmpty ? 'data: [DONE]\n\n' : _sse([chatReply]));
    }
    if (path.endsWith('/comments')) return json([]);
    if (path.startsWith('/api/articles/')) {
      return json({..._article(0), 'clean_text': 'Full text of the story.'});
    }
    return http.Response('not found', 404);
  });
}

Future<void> _settle(WidgetTester tester) async {
  // Sahte istekler mikro görevlerde tamamlanır; birkaç kare yeterli.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpAt(WidgetTester tester, Widget home, Size size) async {
  // Test fontu (Ahem) gerçek fontlardan çok daha geniş olduğundan taşma
  // uyarıları burada anlamlı değil; diğer tüm hatalar testi düşürür.
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: home));
  await _settle(tester);
}

/// Akış (stream) tabanlı istekler sahte zaman ortamında tamamlanmadığı için
/// veriyi ekran çizilmeden önce gerçek zamanda hazırlar.
Future<void> _prime(WidgetTester tester) => tester.runAsync(() async {
  await AppState.instance.ensureFeed();
  await AppState.instance.loadBrief();
});

void _useServer(MockClient client) {
  AppState.instance = AppState(
    api: ApiService(baseUrl: 'https://api.test', client: client),
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _requests.clear();
    _useServer(_server());
  });

  testWidgets('mobile home shows the top story and the brief', (tester) async {
    await _prime(tester);
    await _pumpAt(tester, const HomePage(), const Size(400, 1600));
    expect(find.text('Story number 0 about chips'), findsOneWidget);
    expect(find.text('Cross-Source Brief'), findsOneWidget);
  });

  for (final size in const [
    Size(1200, 700),
    Size(1440, 900),
    Size(1920, 1080),
  ]) {
    for (var page = 0; page < WebShell.pages.length; page++) {
      testWidgets(
        'web page $page @ ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          AppState.instance.goTo(page);
          await _prime(tester);
          await _pumpAt(tester, const WebShell(), size);
          expect(find.text(WebShell.pages[page].label), findsWidgets);
        },
      );
    }
  }

  testWidgets('home renders live data and the cross-source brief', (
    tester,
  ) async {
    await _prime(tester);
    await _pumpAt(tester, const WebShell(), const Size(1440, 900));
    expect(find.text('Story number 0 about chips'), findsOneWidget);
    expect(find.textContaining('Shared Consensus'), findsOneWidget);
  });

  testWidgets('login screen signs the user in', (tester) async {
    await _pumpAt(tester, const WebGate(), const Size(1440, 900));
    expect(find.text('Welcome'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'can_test');
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(AppState.instance.user?.username, 'can_test');
    expect(find.text('WOF Feed'), findsWidgets);
  });

  testWidgets('WAI answers a question about a story', (tester) async {
    final state = AppState.instance;
    await _prime(tester);
    state.askAbout(state.feed.first);
    await _pumpAt(tester, const WebShell(), const Size(1440, 900));

    await tester.runAsync(() => state.send('What is it about?'));
    await _settle(tester);
    // Balonda ve sohbet listesi önizlemesinde görünür. Sunucu kullanıcısı
    // yoksa WAI sohbeti sabit bir girişle açar (+ cevap: iki WAI mesajı).
    expect(find.text('It is about faster chips.'), findsWidgets);
    expect(
      find.text("I've read this story. What would you like to know?"),
      findsOneWidget,
    );
    expect(find.text('Helpful'), findsNWidgets(2));
  });

  testWidgets('WAI tab: areas in three sizes; WAI opens the area chat', (
    tester,
  ) async {
    final state = AppState.instance;
    await tester.runAsync(() => state.login('can_test'));
    state.goTo(AppState.navChat);
    await _pumpAt(tester, const WebShell(), const Size(1440, 900));

    expect(find.text('What do you want to talk about?'), findsOneWidget);
    expect(find.text('YOUR AREAS'), findsOneWidget);
    expect(find.text('YOUR TOPICS'), findsOneWidget);
    expect(find.text('MORE AREAS'), findsOneWidget);
    Size box(String label) => tester.getSize(
      find
          .ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    // Kullanıcının alanı > kullanıcının alt konusu > diğer alan / alt konular.
    final mine = box('Artificial Intelligence');
    final myTopic = box('LLM Agents');
    expect(mine.height, greaterThan(myTopic.height));
    expect(myTopic.height, greaterThan(box('NVIDIA').height));
    expect(box('NVIDIA').height, box('Gaming & Handhelds').height);

    await tester.tap(find.text('Artificial Intelligence'));
    await _settle(tester);
    final open = _requests.singleWhere((r) => r.url.path == '/api/wai/open');
    expect(jsonDecode(open.body), {
      'user_id': 'u1',
      'mode': 'area',
      'area': 'AI',
    });
    // Sohbeti WAI açar; okuduğu haberler sağda numaralı.
    expect(
      find.textContaining('summarize the most striking aspects'),
      findsWidgets,
    );
    expect(find.text('WHAT WAI READ'), findsOneWidget);
    expect(find.text('Summarize the most striking'), findsOneWidget);

    await tester.runAsync(() => state.send('Yes please'));
    await _settle(tester);
    expect(find.textContaining('keeps rising [1].'), findsWidgets);
    final chat = _requests.singleWhere((r) => r.url.path == '/api/wai/chat');
    final body = jsonDecode(chat.body) as Map<String, dynamic>;
    expect(body['source_ids'], ['id-3', 'id-4']);
    expect(body['question'], 'Yes please');
    // "Evet" WAI'nin açılış sorusuna göre anlaşılsın diye açılış geçmişte.
    expect((body['history'] as List).single['role'], 'assistant');
  });

  testWidgets('Latest developments card opens a WAI chat about it', (
    tester,
  ) async {
    final state = AppState.instance;
    await tester.runAsync(() async {
      await state.login('can_test');
      await state.ensureFeed();
      await state.loadBrief();
    });
    state.goTo(AppState.navHome);
    await _pumpAt(tester, const WebShell(), const Size(1440, 900));

    await tester.tap(find.text('Ask WAI about this'));
    await _settle(tester);
    expect(state.navIndex, AppState.navChat);
    expect(state.activeThread?.mode, WaiMode.latest);
    final open = _requests.singleWhere((r) => r.url.path == '/api/wai/open');
    expect((jsonDecode(open.body) as Map)['mode'], 'latest');
    expect(
      find.textContaining('summarize the most striking aspects'),
      findsWidgets,
    );

    // Bir haberden açılan sohbet ayrı: WAI haberin metnini okur.
    state.askAbout(state.feed.first);
    await _settle(tester);
    final story = _requests.lastWhere((r) => r.url.path == '/api/wai/open');
    expect(jsonDecode(story.body), {
      'user_id': 'u1',
      'mode': 'story',
      'article_id': state.feed.first.id,
    });
    expect(state.threads.keys, ['latest', 'story:${state.feed.first.id}']);
    expect(
      find.text('This story is about faster chips. Want the key points?'),
      findsWidgets,
    );
  });

  testWidgets('empty WAI answer shows an English error with Retry', (
    tester,
  ) async {
    _useServer(_server(chatReply: ''));
    final state = AppState.instance;
    await _prime(tester);
    state.askAbout(state.feed.first);
    await _pumpAt(tester, const WebShell(), const Size(1440, 900));

    await tester.runAsync(() => state.send('What is it about?'));
    await _settle(tester);
    expect(find.text('Something went wrong. Please try again.'), findsWidgets);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('onboarding: pick → taste check → your feed is ready', (
    tester,
  ) async {
    _useServer(_server(onboarded: false));
    await _pumpAt(tester, const WebGate(), const Size(1440, 900));
    await tester.enterText(find.byType(TextField), 'new_reader');
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    final state = AppState.instance;

    Future<void> tap(String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.tap(find.text(text));
      await _settle(tester);
    }

    // 1. Seç: seçenekler /api/taxonomy'den.
    expect(state.onboardingStep, OnboardingStep.pick);
    expect(find.text('What do you want to read about?'), findsOneWidget);
    expect(find.text('Pick a category above to see its topics.'), findsOne);
    await tap('Artificial Intelligence');
    await tap('LLM Agents');

    // "+" takip: kendi yazdığı bir şey, kategorisiyle birlikte.
    expect(find.text('Follow something specific'), findsOneWidget);
    final followField = find.byType(TextField).first;
    await tester.enterText(followField, 'www.revolut.com');
    await tap('Add');
    expect(find.text('Type a name, not a link.'), findsOneWidget);
    await tester.enterText(followField, '  Revolut ');
    await tap('Add');
    expect(find.text('Revolut'), findsOneWidget);
    expect(find.textContaining('following Revolut'), findsOneWidget);

    // "Neden" cümlesi: isteğe bağlı; örnek çip alana yazar.
    expect(find.text('What should your feed help you with?'), findsOneWidget);
    await tap('I invest');
    expect(find.widgetWithText(TextField, 'I invest'), findsOneWidget);
    await tap('Continue');

    final put = _requests.singleWhere((r) => r.method == 'PUT');
    expect(put.url.path, '/api/users/u1/preferences');
    expect(jsonDecode(put.body), {
      'preferred_macro_tags': ['AI'],
      'preferred_micro_tags': ['llm_agents'],
      'interest_context': 'I invest',
    });
    // Takip, tercihler kaydedildikten sonra gönderilir.
    final follow = _requests.singleWhere(
      (r) => r.method == 'POST' && r.url.path == '/api/users/u1/follows',
    );
    expect(_requests.indexOf(follow), greaterThan(_requests.indexOf(put)));
    expect(jsonDecode(follow.body), {'name': 'Revolut', 'macro': 'AI'});
    expect(state.follows.map((f) => f.name), ['Revolut']);

    // 2. Tadına bak: sunucu onboarding'i tamamlandı saysa da adımlar sürer.
    expect(state.needsOnboarding, isFalse);
    expect(state.onboardingStep, OnboardingStep.taste);
    expect(find.text('Would you read these?'), findsOneWidget);
    expect(find.text('1 / 6'), findsOneWidget);
    await tap("I'd read this");
    await tap("I'd read this");
    await tap('Not for me');
    await tap('Skip');

    final opinions = [
      for (final r in _requests)
        if (r.url.path.endsWith('/interactions'))
          '${r.url.pathSegments[2]}:'
              '${(jsonDecode(r.body) as Map)['interaction_type']}',
    ];
    expect(opinions, ['id-0:like', 'id-1:like', 'id-2:dislike']);

    // 3. Akışın hazır: güncel profille sıralanmış akış.
    expect(state.onboardingStep, OnboardingStep.reveal);
    expect(find.textContaining('Here is your Feed'), findsOneWidget);
    expect(find.text('Your 60-second brief'), findsOneWidget);
    // Destede görülenler tekrar gösterilmez; beğenilmeyen akıştan çıktı.
    expect(state.revealPicks.map((a) => a.id), ['id-3', 'id-4', 'id-5']);
    // Beğenilerle öğrenilen konular gerekçe olarak görünür.
    expect(find.textContaining('Because you follow'), findsWidgets);
    // Takip edilen şeyden bahseden haberin gerekçesi takibin kendisi.
    expect(find.text('Because you follow Revolut'), findsOneWidget);
    // Akışta haberi olmayan seçili konu: sunucu çekip kaydediyor; canlı web
    // araması (kaydetmeyen, kredi harcayan) yapılmıyor.
    expect(find.textContaining('Collecting fresh stories on'), findsOneWidget);
    expect(
      _requests.any((r) => r.url.queryParameters['live_web'] == 'true'),
      isFalse,
    );

    await tap('Open my Feed');
    expect(state.onboardingStep, isNull);
    expect(state.navIndex, AppState.navFeed);
    expect(state.feed.first.id, 'id-3');
    expect(find.text('WOF Feed'), findsWidgets);

    // Ana sayfa: "Latest developments" kartı onboarding sonunda yazıldı;
    // yanında kartın yazıldığı haberlerin kendi özetleri (Daily Brief).
    // Tavily'li günlük özet artık ana sayfada istenmiyor.
    state.goTo(AppState.navHome);
    await _settle(tester);
    expect(find.text('LATEST DEVELOPMENTS'), findsOneWidget);
    expect(
      find.text('Chipmakers race ahead as AI demand grows'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Demand for AI chips keeps rising'),
      findsOneWidget,
    );
    expect(find.text('Daily Brief'), findsOneWidget);
    expect(find.text('2 stories'), findsOneWidget);
    expect(
      _requests.where((r) => r.url.path.endsWith('/latest-developments')),
      hasLength(1),
    );
    expect(
      _requests.any((r) => r.url.path == '/api/intelligence/daily-digest'),
      isFalse,
    );
    expect(find.text('Picked for you'), findsOneWidget);
  });

  testWidgets('taste check is skipped when there are too few stories', (
    tester,
  ) async {
    _useServer(
      MockClient((req) async {
        final body = switch (req.url.path) {
          '/api/users/login' => {
            'id': 'u1',
            'username': 'x',
            'onboarding_completed': false,
          },
          '/api/users/u1/preferences' => {
            'id': 'u1',
            'username': 'x',
            'onboarding_completed': true,
            'preferred_macro_tags': ['AI'],
          },
          '/api/feed/personalized' => {
            'is_fallback': false,
            'articles': [_article(0), _article(1)],
          },
          _ => <String, Object>{},
        };
        return http.Response(jsonEncode(body), 200);
      }),
    );
    await tester.runAsync(() async {
      await AppState.instance.login('x');
      await AppState.instance.submitOnboardingPicks(
        macroTags: ['AI'],
        microTags: const [],
      );
    });
    // 2 haberle kalibrasyon olmaz; doğrudan açılış ekranı.
    expect(AppState.instance.onboardingStep, OnboardingStep.reveal);
    expect(AppState.instance.revealPicks, hasLength(2));
  });

  testWidgets('swiping right sends a like and shows the match score', (
    tester,
  ) async {
    final state = AppState.instance;
    await tester.runAsync(() async {
      await state.login('can_test');
      await state.ensureFeed();
    });
    state.goTo(AppState.navFeed);
    await _pumpAt(tester, const WebShell(), const Size(1440, 900));

    expect(state.feedIsPersonal, isTrue);
    expect(find.text('90% match'), findsOneWidget);
    expect(find.text('Personalized for you'.toUpperCase()), findsOneWidget);

    await tester.runAsync(() async {
      state.react(state.feed.first, like: true);
      // Kuyruktaki isteğin bitmesini bekle.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    final like = _requests.singleWhere(
      (r) => r.url.path == '/api/articles/id-0/interactions',
    );
    expect(jsonDecode(like.body), {
      'user_id': 'u1',
      'interaction_type': 'like',
    });
    expect(state.isLiked('id-0'), isTrue);

    // Sunucu beğenilen haberin kategorisini tercihlere ekledi; uygulama
    // güncel listeyi gösterir.
    expect(state.interests, ['AI', 'Tech']);
    await tester.pump();
    expect(find.text('Tech'), findsWidgets);
  });

  testWidgets('swiping left sends a dislike and the story leaves the feed', (
    tester,
  ) async {
    final state = AppState.instance;
    await tester.runAsync(() async {
      await state.login('can_test');
      await state.ensureFeed();
    });
    state.goTo(AppState.navFeed);
    await _pumpAt(tester, const WebShell(), const Size(1440, 900));

    await tester.runAsync(() async {
      // Önce beğen, sonra aynı habere sola kaydır.
      state.react(state.feed.first, like: true);
      state.restartFeed();
      state.react(state.feed.first, like: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    final sent = [
      for (final r in _requests)
        if (r.url.path == '/api/articles/id-0/interactions')
          (jsonDecode(r.body) as Map<String, dynamic>)['interaction_type'],
    ];
    expect(sent, ['like', 'dislike']);
    expect(state.isLiked('id-0'), isFalse);
    expect(state.sessionDislikes, 1);

    // Aynı kart "Start over" ile tekrar geçilirse istek tekrar gitmez.
    await tester.runAsync(() async {
      state.restartFeed();
      state.react(state.feed.first, like: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(
      _requests.where((r) => r.url.path == '/api/articles/id-0/interactions'),
      hasLength(2),
    );

    // Yenilenen kişisel akışta beğenilmeyen haber yok.
    await tester.runAsync(state.refreshFeed);
    expect(state.feed.map((a) => a.id), isNot(contains('id-0')));
  });

  testWidgets('profile shows server interests and opens the editor', (
    tester,
  ) async {
    final state = AppState.instance;
    await tester.runAsync(() => state.login('can_test'));
    state.goTo(AppState.navProfile);
    await _pumpAt(tester, const WebShell(), const Size(1440, 900));

    expect(find.text('AI'), findsWidgets);
    expect(find.text('LLM Agents'), findsWidgets);
    expect(
      find.text('Your Feed helps you: “I build products”'),
      findsOneWidget,
    );
    await tester.tap(find.text('Interests'));
    await _settle(tester);
    expect(find.text('Edit interests'), findsOneWidget);
    expect(find.textContaining('will be reset'), findsOneWidget);
    // Kayıtlı cümle düzenleme formunda dolu gelir; silinirse '' gönderilir.
    expect(find.widgetWithText(TextField, 'I build products'), findsOneWidget);
  });

  testWidgets('tunnel down shows Server unavailable', (tester) async {
    _useServer(
      MockClient((_) async => http.Response('503 - Tunnel Unavailable', 503)),
    );
    AppState.instance.goTo(AppState.navFeed);
    await _pumpAt(tester, const WebShell(), const Size(1440, 900));
    expect(find.textContaining('Server unavailable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
