import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../app/ide.dart';
import '../../core/languages.dart';
import '../../services/lsp_service.dart';
import '../../theme/ide_theme.dart';
import '../../workspace/editor_document.dart';
import '../widgets.dart';

enum PromptKind { keyword, snippet, word, method, field, variable, klass, module, property, other }

/// A completion candidate shown in the suggestion widget.
class IdePrompt extends CodePrompt {
  const IdePrompt({required super.word, required this.kind, this.detail, required this.result, this.onAccept});

  final PromptKind kind;
  final String? detail;
  final CodeAutocompleteResult result;

  /// When set, the prompt performs its own insertion (multi-line snippets
  /// with tab stops) instead of the editor's plain word replacement.
  final VoidCallback? onAccept;

  @override
  CodeAutocompleteResult get autocomplete {
    if (onAccept != null) {
      // Called exactly when the user picks this prompt.
      scheduleMicrotask(onAccept!);
      return const CodeAutocompleteResult(input: '', word: '', selection: TextSelection.collapsed(offset: 0));
    }
    return result;
  }

  @override
  bool match(String input) => true;

  static PromptKind fromLsp(int k) => switch (k) {
        2 || 3 || 4 => PromptKind.method,
        5 => PromptKind.field,
        6 => PromptKind.variable,
        7 || 8 || 22 || 25 => PromptKind.klass,
        9 => PromptKind.module,
        10 => PromptKind.property,
        14 => PromptKind.keyword,
        15 => PromptKind.snippet,
        _ => PromptKind.other,
      };
}

/// Builds suggestions from the language server, snippets, keywords and words
/// already present in the document.
class IdePromptsBuilder implements CodeAutocompletePromptsBuilder {
  IdePromptsBuilder({required this.ide, required this.doc});

  final Ide ide;
  final EditorDocument doc;

  Set<String>? _keywords;
  Set<String> _words = {};
  int _wordsVersion = -1;
  List<LspCompletion> _lspCache = [];
  String _lspKey = '';
  int _lspRequest = 0;

  Set<String> _languageKeywords(LanguageDef l) {
    final Set<String> out = {};
    final dynamic kw = l.mode.keywords;
    void addAll(dynamic v) {
      if (v is String) {
        out.addAll(v.split(RegExp(r'\s+')).where((s) => s.length > 1).map((s) => s.split('|').first));
      } else if (v is List) {
        for (final dynamic e in v) {
          if (e is String) out.add(e.split('|').first);
        }
      }
    }

    if (kw is Map) {
      for (final String k in ['keyword', 'built_in', 'literal', 'type']) {
        addAll(kw[k]);
      }
    } else {
      addAll(kw);
    }
    return out;
  }

  void _refreshWords() {
    if (_wordsVersion == doc.version) return;
    _wordsVersion = doc.version;
    final Set<String> words = {};
    final RegExp re = RegExp(r'[A-Za-z_][A-Za-z0-9_]{2,}');
    final String text = doc.text;
    if (text.length < 600000) {
      for (final RegExpMatch m in re.allMatches(text)) {
        words.add(m.group(0)!);
        if (words.length > 4000) break;
      }
    }
    _words = words;
  }

  static bool _isIdent(int c) => (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36;

  @override
  CodeAutocompleteEditingValue? build(BuildContext context, CodeLine codeLine, CodeLineSelection selection) {
    final String text = codeLine.text;
    final int caret = selection.extentOffset.clamp(0, text.length);
    int start = caret;
    while (start > 0 && _isIdent(text.codeUnitAt(start - 1))) {
      start--;
    }
    final String input = text.substring(start, caret);
    final bool afterDot = start > 0 && (text[start - 1] == '.' || (start > 1 && text.substring(start - 2, start) == '->') || (start > 1 && text.substring(start - 2, start) == '::'));
    if (input.isEmpty && !afterDot) return null;
    // Skip inside line comments.
    final String? lc = doc.language.lineComment;
    if (lc != null && text.substring(0, start).contains(lc)) return null;

    final LanguageDef lang = doc.language;
    final bool enabled = ide.extensions.isLanguageEnabled(lang);
    _requestLsp(selection.extentIndex, caret, start);

    final String low = input.toLowerCase();
    final List<IdePrompt> out = [];
    final Set<String> seen = {};

    void add(IdePrompt p) {
      if (seen.add('${p.kind.index}:${p.word}')) out.add(p);
    }

    final String lspKey = '${selection.extentIndex}:$start';
    if (_lspKey == lspKey) {
      for (final LspCompletion c in _lspCache) {
        final String label = c.label;
        if (low.isNotEmpty && !label.toLowerCase().startsWith(low) && !label.toLowerCase().contains(low)) continue;
        if (label == input) continue;
        final String insert = _plainInsert(c.insertText ?? label, c.isSnippet);
        add(IdePrompt(
          word: label,
          kind: IdePrompt.fromLsp(c.kind),
          detail: c.detail,
          result: _result(insert, input, c.isSnippet ? c.insertText : null),
        ));
        if (out.length > 60) break;
      }
    }
    if (!afterDot && enabled) {
      for (final Snippet s in [...lang.snippets, ...?ide.extensions.extraSnippets[lang.id]]) {
        if (s.prefix.toLowerCase().startsWith(low)) {
          final int line = selection.extentIndex;
          add(IdePrompt(
            word: s.prefix,
            kind: PromptKind.snippet,
            detail: s.label,
            result: _result(s.prefix, input, null),
            onAccept: () {
              doc.controller.selection = CodeLineSelection(baseIndex: line, baseOffset: start, extentIndex: line, extentOffset: caret);
              ide.insertSnippet(doc, s.body);
            },
          ));
        }
      }
      _keywords ??= _languageKeywords(lang);
      for (final String k in _keywords!) {
        if (k.length > input.length && k.toLowerCase().startsWith(low)) {
          add(IdePrompt(word: k, kind: PromptKind.keyword, result: _result(k, input, null)));
        }
      }
    }
    if (input.length >= 2) {
      _refreshWords();
      int n = 0;
      for (final String w in _words) {
        if (w != input && w.length > input.length && w.toLowerCase().startsWith(low) && !seen.contains('${PromptKind.keyword.index}:$w')) {
          add(IdePrompt(word: w, kind: PromptKind.word, result: _result(w, input, null)));
          if (++n > 30) break;
        }
      }
    }
    if (out.isEmpty) return null;
    out.sort((a, b) {
      int rank(IdePrompt p) => switch (p.kind) {
            PromptKind.snippet => 0,
            PromptKind.word => 3,
            PromptKind.keyword => 2,
            _ => 1,
          };
      final bool ap = a.word.startsWith(input), bp = b.word.startsWith(input);
      if (ap != bp) return ap ? -1 : 1;
      final int r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return a.word.length.compareTo(b.word.length);
    });
    return CodeAutocompleteEditingValue(input: input, prompts: out.take(80).toList(), index: 0);
  }

  void _requestLsp(int line, int caret, int start) {
    final LspClient? client = ide.lsp.clientFor(doc);
    if (client == null) return;
    final String key = '$line:$start';
    if (key == _lspKey && _lspCache.isNotEmpty) return;
    final int req = ++_lspRequest;
    ide.lsp.flush(doc);
    client.completion(doc, line, caret).then((items) {
      if (req != _lspRequest) return;
      _lspKey = key;
      _lspCache = items;
    });
  }

  /// Converts an LSP snippet ("foo(${1:x})") into plain text.
  static String _plainInsert(String s, bool snippet) {
    if (!snippet) return s;
    return s.replaceAllMapped(RegExp(r'\$\{\d+:([^}]*)\}'), (m) => m.group(1)!).replaceAll(RegExp(r'\$\{?\d+\}?'), '');
  }

  static CodeAutocompleteResult _result(String word, String input, String? snippet) {
    int caret = word.length;
    if (snippet != null) {
      final int i = snippet.indexOf(RegExp(r'\$\{?1'));
      if (i >= 0) caret = _plainInsert(snippet.substring(0, i), true).length;
    }
    return CodeAutocompleteResult(input: '', word: word, selection: TextSelection.collapsed(offset: caret));
  }
}

/// The suggestion list widget.
class SuggestList extends StatefulWidget implements PreferredSizeWidget {
  const SuggestList({super.key, required this.notifier, required this.onSelected, required this.theme, required this.fontFamily});

  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;
  final IdeTheme theme;
  final String fontFamily;

  static const double itemH = 24;

  @override
  Size get preferredSize => Size(400, math.min(itemH * notifier.value.prompts.length, itemH * 10) + 10);

  @override
  State<SuggestList> createState() => _SuggestListState();
}

class _SuggestListState extends State<SuggestList> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_changed);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final int i = widget.notifier.value.index;
    if (!_scroll.hasClients) return;
    final double top = i * SuggestList.itemH;
    final double view = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (top + SuggestList.itemH > _scroll.offset + view) {
      _scroll.jumpTo(top + SuggestList.itemH - view);
    }
  }

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = widget.theme;
    final CodeAutocompleteEditingValue v = widget.notifier.value;
    return Container(
      width: widget.preferredSize.width,
      height: widget.preferredSize.height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border),
        boxShadow: [BoxShadow(color: t.shadow, blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: ListView.builder(
        controller: _scroll,
        itemExtent: SuggestList.itemH,
        itemCount: v.prompts.length,
        padding: EdgeInsets.zero,
        itemBuilder: (context, i) {
          final CodePrompt p = v.prompts[i];
          final bool sel = i == v.index;
          final PromptKind kind = p is IdePrompt ? p.kind : PromptKind.other;
          final String? detail = p is IdePrompt ? p.detail : null;
          return GestureDetector(
            onTap: () => widget.onSelected(v.copyWith(index: i).autocomplete),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(color: sel ? t.accentSoft : null, borderRadius: BorderRadius.circular(5)),
              child: Row(children: [
                _KindIcon(kind: kind, theme: t),
                const SizedBox(width: 8),
                Expanded(child: _highlighted(t, p.word, v.input)),
                if (detail != null)
                  Flexible(
                    child: Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(t, size: 11.5, color: t.textFaint)),
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _highlighted(IdeTheme t, String word, String input) {
    final TextStyle base = TextStyle(fontFamily: widget.fontFamily, fontFamilyFallback: const ['JetBrains Mono', 'Consolas'], fontSize: 13, color: t.text);
    final int n = input.isNotEmpty && word.toLowerCase().startsWith(input.toLowerCase()) ? input.length : 0;
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: base, children: [
        TextSpan(text: word.substring(0, n), style: TextStyle(color: t.accent, fontWeight: FontWeight.w700)),
        TextSpan(text: word.substring(n)),
      ]),
    );
  }
}

class _KindIcon extends StatelessWidget {
  const _KindIcon({required this.kind, required this.theme});

  final PromptKind kind;
  final IdeTheme theme;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (kind) {
      PromptKind.snippet => (Icons.content_paste_go_rounded, theme.palette.string),
      PromptKind.keyword => (Icons.key_rounded, theme.palette.keyword),
      PromptKind.method => (Icons.functions_rounded, theme.palette.function),
      PromptKind.field || PromptKind.property => (Icons.label_outline_rounded, theme.palette.variable),
      PromptKind.variable => (Icons.data_object_rounded, theme.palette.variable),
      PromptKind.klass => (Icons.category_rounded, theme.palette.type),
      PromptKind.module => (Icons.inventory_2_outlined, theme.palette.type),
      PromptKind.word => (Icons.notes_rounded, theme.textFaint),
      PromptKind.other => (Icons.circle_outlined, theme.textMuted),
    };
    return Icon(icon, size: 14, color: color);
  }
}
