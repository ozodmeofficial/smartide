import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../workspace/workspace.dart';
import 'output_service.dart';

/// Built-in static file server with automatic browser reload, similar to the
/// popular "Live Server" VS Code extension.
class LiveServer extends ChangeNotifier {
  LiveServer(this.workspace, this.output) {
    workspace.onFilesChanged.add(_broadcastReload);
    workspace.onDocumentSaved.add((_) => _broadcastReload());
  }

  final Workspace workspace;
  final OutputService output;

  HttpServer? _server;
  final List<HttpResponse> _clients = [];
  int port = 5500;
  String? _root;
  Timer? _debounce;

  bool get running => _server != null;
  String get url => 'http://127.0.0.1:$port/';

  static const String _endpoint = '/__smartide_live';
  static const String _script = '''
<!-- Injected by SmartIDE Live Server -->
<script>
(function(){
  if (!window.EventSource) return;
  var es = new EventSource('$_endpoint');
  es.onmessage = function(e){
    if (e.data === 'css') {
      document.querySelectorAll('link[rel="stylesheet"]').forEach(function(l){
        var u = new URL(l.href); u.searchParams.set('_r', Date.now()); l.href = u.toString();
      });
    } else if (e.data === 'reload') { location.reload(); }
  };
})();
</script>
''';

  Future<bool> start({String? root, int preferredPort = 5500, String? openPath}) async {
    if (running) await stop();
    _root = root ?? workspace.root;
    if (_root == null) return false;
    for (int candidate = preferredPort; candidate < preferredPort + 20; candidate++) {
      try {
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, candidate);
        port = candidate;
        break;
      } catch (_) {}
    }
    if (_server == null) return false;
    _server!.listen(_handle, onError: (_) {});
    output.append('Live Server', 'Serving $_root at $url');
    notifyListeners();
    String target = url;
    if (openPath != null && p.isWithin(_root!, openPath)) {
      target = '$url${p.relative(openPath, from: _root).replaceAll('\\', '/')}';
    }
    openInBrowser(target);
    return true;
  }

  Future<void> stop() async {
    for (final HttpResponse c in _clients) {
      try {
        await c.close();
      } catch (_) {}
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
    output.append('Live Server', 'Stopped');
    notifyListeners();
  }

  static void openInBrowser(String url) {
    if (Platform.isWindows) {
      Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
    } else if (Platform.isMacOS) {
      Process.run('open', [url]);
    } else {
      Process.run('xdg-open', [url]);
    }
  }

  void _broadcastReload() {
    if (!running) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      for (final HttpResponse c in _clients.toList()) {
        try {
          c.write('data: reload\n\n');
          c.flush();
        } catch (_) {
          _clients.remove(c);
        }
      }
    });
  }

  Future<void> _handle(HttpRequest req) async {
    final HttpResponse res = req.response;
    res.headers.set('Cache-Control', 'no-store');
    if (req.uri.path == _endpoint) {
      res.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
      res.headers.set('Connection', 'keep-alive');
      res.bufferOutput = false;
      res.write('retry: 1000\n\n');
      await res.flush();
      _clients.add(res);
      res.done.whenComplete(() => _clients.remove(res));
      return;
    }
    try {
      String rel = Uri.decodeComponent(req.uri.path);
      if (rel.startsWith('/')) rel = rel.substring(1);
      final String full = p.normalize(p.join(_root!, rel));
      if (!p.isWithin(_root!, full) && full != p.normalize(_root!)) {
        res.statusCode = HttpStatus.forbidden;
        await res.close();
        return;
      }
      if (await Directory(full).exists()) {
        final File index = File(p.join(full, 'index.html'));
        if (await index.exists()) {
          if (!req.uri.path.endsWith('/')) {
            res.redirect(req.uri.replace(path: '${req.uri.path}/'));
            return;
          }
          await _sendFile(res, index);
        } else {
          await _sendListing(res, Directory(full), req.uri.path);
        }
        return;
      }
      final File f = File(full);
      if (!await f.exists()) {
        res.statusCode = HttpStatus.notFound;
        res.headers.contentType = ContentType.html;
        res.write('<h2 style="font-family:sans-serif">404 — ${htmlEscape.convert(rel)} not found</h2>$_script');
        await res.close();
        return;
      }
      await _sendFile(res, f);
    } catch (e) {
      res.statusCode = HttpStatus.internalServerError;
      res.write('$e');
      await res.close();
    }
  }

  Future<void> _sendFile(HttpResponse res, File f) async {
    final String ext = p.extension(f.path).toLowerCase();
    final String mime = _mime[ext] ?? 'application/octet-stream';
    res.headers.set('Content-Type', mime);
    if (ext == '.html' || ext == '.htm') {
      String html = await f.readAsString();
      final int idx = html.toLowerCase().lastIndexOf('</body>');
      html = idx >= 0 ? html.substring(0, idx) + _script + html.substring(idx) : html + _script;
      res.write(html);
    } else {
      await res.addStream(f.openRead());
    }
    await res.close();
  }

  Future<void> _sendListing(HttpResponse res, Directory d, String urlPath) async {
    final List<FileSystemEntity> items = await d.list().toList();
    items.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    final StringBuffer sb = StringBuffer(
        '<!doctype html><meta charset="utf-8"><title>${htmlEscape.convert(urlPath)}</title>'
        '<style>body{font-family:Segoe UI,system-ui,sans-serif;background:#faf9f5;color:#2b2a27;max-width:760px;margin:40px auto;padding:0 16px}'
        'a{color:#c96442;text-decoration:none;display:block;padding:6px 10px;border-radius:8px}a:hover{background:#f0eee6}</style>'
        '<h2>Index of ${htmlEscape.convert(urlPath)}</h2>');
    if (urlPath != '/') sb.write('<a href="../">../</a>');
    for (final FileSystemEntity e in items) {
      final String name = p.basename(e.path) + (e is Directory ? '/' : '');
      sb.write('<a href="${Uri.encodeComponent(p.basename(e.path))}${e is Directory ? '/' : ''}">${htmlEscape.convert(name)}</a>');
    }
    sb.write(_script);
    res.headers.contentType = ContentType.html;
    res.write(sb.toString());
    await res.close();
  }

  static const Map<String, String> _mime = {
    '.html': 'text/html; charset=utf-8',
    '.htm': 'text/html; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.mjs': 'text/javascript; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.map': 'application/json',
    '.svg': 'image/svg+xml',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.ico': 'image/x-icon',
    '.woff': 'font/woff',
    '.woff2': 'font/woff2',
    '.ttf': 'font/ttf',
    '.otf': 'font/otf',
    '.txt': 'text/plain; charset=utf-8',
    '.md': 'text/plain; charset=utf-8',
    '.xml': 'application/xml',
    '.pdf': 'application/pdf',
    '.mp4': 'video/mp4',
    '.webm': 'video/webm',
    '.mp3': 'audio/mpeg',
    '.wav': 'audio/wav',
    '.wasm': 'application/wasm',
  };
}
