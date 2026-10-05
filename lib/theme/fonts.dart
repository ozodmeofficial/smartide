import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/paths.dart';

enum FontSource { bundled, system, download }

class CodeFont {
  const CodeFont(this.family, this.source, {this.file, this.note = '', this.ligatures = false});

  final String family;
  final FontSource source;

  /// Path inside the google/fonts repository (or full URL) for downloadable fonts.
  final String? file;
  final String note;
  final bool ligatures;

  String get cacheFile => p.join(AppPaths.fontsDir, '${family.replaceAll(' ', '')}.ttf');
}

/// Programming fonts offered in Settings. Only JetBrains Mono ships inside the
/// app (~180 KB); the rest are fetched on first use and cached, which keeps the
/// installer small.
const List<CodeFont> codeFonts = [
  CodeFont('JetBrains Mono', FontSource.bundled, note: 'Default · built in', ligatures: true),
  CodeFont('Cascadia Code', FontSource.download, file: 'ofl/cascadiacode/CascadiaCode%5Bwght%5D.ttf', note: 'Microsoft', ligatures: true),
  CodeFont('Fira Code', FontSource.download, file: 'ofl/firacode/FiraCode%5Bwght%5D.ttf', note: 'Ligatures', ligatures: true),
  CodeFont('Source Code Pro', FontSource.download, file: 'ofl/sourcecodepro/SourceCodePro%5Bwght%5D.ttf', note: 'Adobe'),
  CodeFont('IBM Plex Mono', FontSource.download, file: 'ofl/ibmplexmono/IBMPlexMono-Regular.ttf', note: 'IBM'),
  CodeFont('Roboto Mono', FontSource.download, file: 'ofl/robotomono/RobotoMono%5Bwght%5D.ttf', note: 'Google'),
  CodeFont('Geist Mono', FontSource.download, file: 'ofl/geistmono/GeistMono%5Bwght%5D.ttf', note: 'Vercel'),
  CodeFont('Victor Mono', FontSource.download, file: 'ofl/victormono/VictorMono%5Bwght%5D.ttf', note: 'Cursive italics', ligatures: true),
  CodeFont('Hack', FontSource.download, file: 'https://raw.githubusercontent.com/source-foundry/Hack/master/build/ttf/Hack-Regular.ttf', note: 'Classic'),
  CodeFont('Inconsolata', FontSource.download, file: 'ofl/inconsolata/Inconsolata%5Bwdth,wght%5D.ttf', note: 'Compact'),
  CodeFont('Ubuntu Mono', FontSource.download, file: 'ufl/ubuntumono/UbuntuMono-Regular.ttf', note: 'Canonical'),
  CodeFont('Space Mono', FontSource.download, file: 'ofl/spacemono/SpaceMono-Regular.ttf', note: 'Retro'),
  CodeFont('Red Hat Mono', FontSource.download, file: 'ofl/redhatmono/RedHatMono%5Bwght%5D.ttf', note: 'Red Hat'),
  CodeFont('Intel One Mono', FontSource.download, file: 'ofl/intelonemono/IntelOneMono%5Bwght%5D.ttf', note: 'Legibility'),
  CodeFont('Martian Mono', FontSource.download, file: 'ofl/martianmono/MartianMono%5Bwdth,wght%5D.ttf', note: 'Wide'),
  CodeFont('DM Mono', FontSource.download, file: 'ofl/dmmono/DMMono-Regular.ttf', note: 'Light'),
  CodeFont('Fira Mono', FontSource.download, file: 'ofl/firamono/FiraMono-Regular.ttf', note: 'Mozilla'),
  CodeFont('Anonymous Pro', FontSource.download, file: 'ofl/anonymouspro/AnonymousPro-Regular.ttf', note: 'Small sizes'),
  CodeFont('Cousine', FontSource.download, file: 'ofl/cousine/Cousine-Regular.ttf', note: 'Metric compatible'),
  CodeFont('Sometype Mono', FontSource.download, file: 'ofl/sometypemono/SometypeMono%5Bwght%5D.ttf', note: 'Friendly'),
  CodeFont('Courier Prime', FontSource.download, file: 'ofl/courierprime/CourierPrime-Regular.ttf', note: 'Typewriter'),
  CodeFont('Consolas', FontSource.system, note: 'Windows system font'),
  CodeFont('Cascadia Mono', FontSource.system, note: 'Windows 11 system font'),
  CodeFont('Lucida Console', FontSource.system, note: 'Windows system font'),
  CodeFont('Courier New', FontSource.system, note: 'Windows system font'),
];

/// Loads code fonts on demand and caches downloaded files on disk.
class FontManager extends ChangeNotifier {
  final Set<String> _loaded = {'JetBrains Mono'};
  final Set<String> _loading = {};
  final Map<String, String> _errors = {};

  bool isLoaded(String family) =>
      _loaded.contains(family) || codeFonts.any((f) => f.family == family && f.source == FontSource.system);
  bool isLoading(String family) => _loading.contains(family);
  String? errorFor(String family) => _errors[family];

  bool isCached(CodeFont font) => font.source != FontSource.download || File(font.cacheFile).existsSync();

  /// Fallback chain used for every code text style.
  static const List<String> fallback = ['JetBrains Mono', 'Cascadia Mono', 'Consolas', 'Menlo', 'monospace'];

  Future<void> ensure(String family) async {
    if (isLoaded(family) || _loading.contains(family)) return;
    final CodeFont? font = codeFonts.where((f) => f.family == family).firstOrNull;
    if (font == null || font.source != FontSource.download) return;
    _loading.add(family);
    _errors.remove(family);
    notifyListeners();
    try {
      final File cache = File(font.cacheFile);
      if (!await cache.exists() || await cache.length() < 1024) {
        final Uint8List bytes = await _download(font.file!);
        await cache.writeAsBytes(bytes, flush: true);
      }
      final FontLoader loader = FontLoader(family)
        ..addFont(cache.readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
      _loaded.add(family);
    } catch (e) {
      _errors[family] = 'Could not download font: $e';
    } finally {
      _loading.remove(family);
      notifyListeners();
    }
  }

  static Future<Uint8List> _download(String file) async {
    final List<String> urls = file.startsWith('http')
        ? [file]
        : [
            'https://raw.githubusercontent.com/google/fonts/main/$file',
            'https://cdn.jsdelivr.net/gh/google/fonts@main/$file',
          ];
    Object? lastError;
    for (final String url in urls) {
      try {
        final HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
        final HttpClientRequest req = await client.getUrl(Uri.parse(url));
        final HttpClientResponse res = await req.close();
        if (res.statusCode != 200) {
          lastError = 'HTTP ${res.statusCode}';
          client.close(force: true);
          continue;
        }
        final BytesBuilder builder = BytesBuilder(copy: false);
        await for (final List<int> chunk in res) {
          builder.add(chunk);
        }
        client.close();
        return builder.takeBytes();
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? 'unknown error';
  }
}
