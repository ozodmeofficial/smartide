import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../workspace/workspace.dart';

class SearchMatch {
  const SearchMatch(this.line, this.start, this.end, this.preview);

  /// 0-based line and column range.
  final int line;
  final int start;
  final int end;
  final String preview;
}

class FileMatches {
  FileMatches(this.path, this.matches);

  final String path;
  final List<SearchMatch> matches;
  bool collapsed = false;
}

/// Find / replace across all files in the workspace.
class SearchService extends ChangeNotifier {
  SearchService(this.workspace);

  final Workspace workspace;

  String query = '';
  String replacement = '';
  String include = '';
  String exclude = '';
  bool caseSensitive = false;
  bool wholeWord = false;
  bool regex = false;
  bool searching = false;
  String? error;
  List<FileMatches> results = [];
  int _generation = 0;

  int get totalMatches => results.fold(0, (s, f) => s + f.matches.length);

  RegExp? _pattern() {
    if (query.isEmpty) return null;
    String src = regex ? query : RegExp.escape(query);
    if (wholeWord) src = '\\b$src\\b';
    try {
      return RegExp(src, caseSensitive: caseSensitive, multiLine: false);
    } catch (e) {
      error = 'Invalid regular expression';
      return null;
    }
  }

  bool _globMatch(String rel, String globs) {
    if (globs.trim().isEmpty) return true;
    for (final String g in globs.split(',')) {
      final String t = g.trim();
      if (t.isEmpty) continue;
      final String re = '^${RegExp.escape(t).replaceAll(r'\*\*', '.*').replaceAll(r'\*', r'[^/\\]*').replaceAll(r'\?', '.')}\$';
      if (RegExp(re, caseSensitive: false).hasMatch(rel) || rel.toLowerCase().contains(t.toLowerCase())) return true;
    }
    return false;
  }

  Future<void> search() async {
    final int gen = ++_generation;
    error = null;
    final RegExp? pattern = _pattern();
    if (pattern == null) {
      results = [];
      searching = false;
      notifyListeners();
      return;
    }
    searching = true;
    results = [];
    notifyListeners();
    final List<String> files = await workspace.listAllFiles();
    int scanned = 0;
    for (final String path in files) {
      if (gen != _generation) return;
      final String rel = workspace.relative(path).replaceAll('\\', '/');
      if (include.isNotEmpty && !_globMatch(rel, include)) continue;
      if (exclude.isNotEmpty && _globMatch(rel, exclude)) continue;
      final File f = File(path);
      try {
        if (await f.length() > 2 * 1024 * 1024) continue;
        final List<int> bytes = await f.readAsBytes();
        if (bytes.take(4000).contains(0)) continue;
        final String text = utf8.decode(bytes, allowMalformed: true);
        final List<SearchMatch> matches = [];
        final List<String> lines = text.split('\n');
        for (int i = 0; i < lines.length && matches.length < 500; i++) {
          final String line = lines[i];
          for (final RegExpMatch m in pattern.allMatches(line)) {
            if (m.end == m.start) continue;
            matches.add(SearchMatch(i, m.start, m.end, line.length > 400 ? line.substring(0, 400) : line));
          }
        }
        if (matches.isNotEmpty) {
          results.add(FileMatches(path, matches));
          if (results.length % 20 == 0) notifyListeners();
        }
      } catch (_) {}
      if (++scanned % 200 == 0) await Future<void>.delayed(Duration.zero);
    }
    if (gen != _generation) return;
    searching = false;
    notifyListeners();
  }

  /// Replaces every match in every file (open documents included).
  Future<int> replaceAll() async {
    final RegExp? pattern = _pattern();
    if (pattern == null) return 0;
    int count = 0;
    for (final FileMatches fm in results) {
      final doc = workspace.openDocuments.where((d) => d.path == fm.path).firstOrNull;
      if (doc != null) {
        final String before = doc.text;
        final String after = before.replaceAllMapped(pattern, (m) => _expand(m));
        if (after != before) {
          doc.controller.runRevocableOp(() => doc.controller.text = after);
          count += fm.matches.length;
          await workspace.saveDocument(doc);
        }
        continue;
      }
      final File f = File(fm.path);
      final String before = await f.readAsString();
      final String after = before.replaceAllMapped(pattern, (m) => _expand(m));
      if (after != before) {
        await f.writeAsString(after);
        count += fm.matches.length;
      }
    }
    await search();
    return count;
  }

  String _expand(Match m) {
    if (!regex) return replacement;
    return replacement.replaceAllMapped(RegExp(r'\$(\d)'), (g) => m.group(int.parse(g.group(1)!)) ?? '');
  }

  void dismiss(FileMatches f) {
    results.remove(f);
    notifyListeners();
  }
}
