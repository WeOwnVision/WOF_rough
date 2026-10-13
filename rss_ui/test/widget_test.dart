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

/// Sunucuyu taklit eden istemci. [chatReply] boşsa chat boş akış döndürür.
MockClient _server({String chatReply = 'It is about faster chips.'}) =>
    MockClient((req) async {
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
        return json({
          'query': req.url.queryParameters['q'],
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
      if (path == '/api/users/login') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        return json({
          'id': 'u1',
          'username': body['username'],
          'avatar_url': null,
        });
      }
      if (path == '/api/intelligence/synthesize') {
        return sse(_sse(['**1. Shared Consensus**\n', '- Chips are faster.']));
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
    // Balonda ve sohbet listesi önizlemesinde görünür.
    expect(find.text('It is about faster chips.'), findsWidgets);
    expect(find.text('Helpful'), findsOneWidget);
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
