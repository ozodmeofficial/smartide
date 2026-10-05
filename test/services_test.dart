import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartide/core/paths.dart';
import 'package:smartide/core/settings.dart';
import 'package:smartide/services/live_server.dart';
import 'package:smartide/services/output_service.dart';
import 'package:smartide/services/search_service.dart';
import 'package:smartide/workspace/workspace.dart';

void main() {
  late Directory tmp;
  late Workspace ws;

  setUpAll(AppPaths.init);

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('smartide_svc');
    File('${tmp.path}/index.html').writeAsStringSync('<html><body><h1>Hi</h1></body></html>');
    File('${tmp.path}/app.js').writeAsStringSync('const greeting = "hello";\nconsole.log(greeting);\n');
    Directory('${tmp.path}/node_modules').createSync();
    File('${tmp.path}/node_modules/lib.js').writeAsStringSync('greeting');
    ws = Workspace(Settings());
    await ws.openFolder(tmp.path);
  });

  tearDown(() {
    ws.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('workspace tree hides excluded folders', () {
    final List<String> names = ws.tree!.children!.map((c) => c.name).toList();
    expect(names, containsAll(['app.js', 'index.html']));
    expect(names, isNot(contains('node_modules')));
  });

  test('search finds matches and skips excluded folders', () async {
    final SearchService s = SearchService(ws)..query = 'greeting';
    await s.search();
    expect(s.results, hasLength(1));
    expect(s.totalMatches, 2);
    s
      ..query = 'GREETING'
      ..caseSensitive = true;
    await s.search();
    expect(s.results, isEmpty);
  });

  test('search and replace rewrites files', () async {
    final SearchService s = SearchService(ws)
      ..query = 'greeting'
      ..replacement = 'message';
    await s.search();
    final int n = await s.replaceAll();
    expect(n, 2);
    expect(File('${tmp.path}/app.js').readAsStringSync(), contains('const message'));
  });

  test('live server serves files and injects the reload script', () async {
    final LiveServer live = LiveServer(ws, OutputService());
    // openInBrowser is a no-op in tests because xdg-open may be missing.
    final bool ok = await live.start(root: tmp.path, preferredPort: 5610);
    expect(ok, isTrue);
    final HttpClient c = HttpClient();
    final HttpClientResponse r = await (await c.getUrl(Uri.parse(live.url))).close();
    final String html = await r.transform(utf8.decoder).join();
    expect(r.statusCode, 200);
    expect(html, contains('<h1>Hi</h1>'));
    expect(html, contains('__smartide_live'));
    final HttpClientResponse js = await (await c.getUrl(Uri.parse('${live.url}app.js'))).close();
    expect(js.headers.contentType?.mimeType, 'text/javascript');
    await js.drain<void>();
    final HttpClientResponse missing = await (await c.getUrl(Uri.parse('${live.url}nope.txt'))).close();
    expect(missing.statusCode, 404);
    await missing.drain<void>();
    c.close();
    await live.stop();
  });

  test('file operations: create, rename, delete', () async {
    final String? path = await ws.createFile(tmp.path, 'src/new.py');
    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);
    expect(ws.activeDocument?.language.id, 'python');
    expect(await ws.rename(path, 'renamed.py'), isTrue);
    expect(File('${tmp.path}/src/renamed.py').existsSync(), isTrue);
    expect(ws.activeDocument?.path, endsWith('renamed.py'));
    await ws.delete('${tmp.path}/src');
    expect(Directory('${tmp.path}/src').existsSync(), isFalse);
    expect(ws.activeTab, isNull);
  });
}
