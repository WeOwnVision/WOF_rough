// Giriş uç noktasının hızını ölçer: dart run bin/test_login.dart [kullanici]
// ignore_for_file: avoid_print
import 'package:rss_ui/services/api_service.dart';

Future<void> main(List<String> args) async {
  final api = ApiService(logger: print);
  final sw = Stopwatch()..start();
  try {
    final user = await api.login(args.isNotEmpty ? args.first : 'test_speed');
    print(
      'Logged in as ${user.username} (${user.id}) in ${sw.elapsedMilliseconds} ms',
    );
  } on ApiException catch (e) {
    print('Failed after ${sw.elapsedMilliseconds} ms: $e');
  } finally {
    api.dispose();
  }
}
