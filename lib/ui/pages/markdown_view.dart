import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:re_highlight/re_highlight.dart';

import '../../app/ide.dart';
import '../../core/languages.dart';
import '../../services/live_server.dart';
import '../../theme/ide_theme.dart';
import '../../workspace/editor_document.dart';
import '../../workspace/workspace.dart';
import '../widgets.dart';

final Highlight _highlight = () {
  final Highlight h = Highlight();
  for (final LanguageDef l in languages) {
    h.registerLanguage(l.id, l.mode);
  }
  return h;
}();

const Map<String, String> _langAliases = {
  'py': 'python',
  'js': 'javascript',
  'ts': 'typescript',
  'c++': 'cpp',
  'cs': 'csharp',
  'c#': 'csharp',
  'sh': 'shell',
  'bash': 'shell',
  'ps1': 'powershell',
  'ps': 'powershell',
  'yml': 'yaml',
  'rs': 'rust',
  'golang': 'go',
  'htm': 'html',
  'md': 'markdown',
  'kt': 'kotlin',
  'rb': 'ruby',
  'cmd': 'bat',
  'jsx': 'javascript',
  'tsx': 'typescript',
};

TextSpan highlightCode(String code, String? lang, IdeTheme t, TextStyle base) {
  final String id = _langAliases[lang?.toLowerCase()] ?? (lang?.toLowerCase() ?? '');
  if (languageById(id) == null) return TextSpan(text: code, style: base);
  try {
    final HighlightResult r = _highlight.highlight(code: code, language: id);
    final TextSpanRenderer renderer = TextSpanRenderer(base, t.syntax);
    r.render(renderer);
    return renderer.span ?? TextSpan(text: code, style: base);
  } catch (_) {
    return TextSpan(text: code, style: base);
  }
}

/// Lightweight Markdown renderer (headings, lists, quotes, tables, code
/// blocks with syntax highlighting, inline emphasis and links).
class MarkdownBody extends StatelessWidget {
  const MarkdownBody({super.key, required this.text, this.fontSize = 14, this.codeActions});

  final String text;
  final double fontSize;

  /// Builds extra buttons for fenced code blocks (copy / insert).
  final List<Widget> Function(String code, String? lang)? codeActions;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final List<Widget> out = [];
    final List<String> lines = text.replaceAll('\r\n', '\n').split('\n');
    int i = 0;
    final List<String> para = [];

    void flushPara() {
      if (para.isEmpty) return;
      out.add(_block(SelectableText.rich(_inline(t, para.join(' '), _base(t)), style: _base(t))));
      para.clear();
    }

    while (i < lines.length) {
      final String line = lines[i];
      final String trimmed = line.trimLeft();
      if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
        flushPara();
        final String fence = trimmed.substring(0, 3);
        final String lang = trimmed.substring(3).trim();
        final List<String> code = [];
        i++;
        while (i < lines.length && !lines[i].trimLeft().startsWith(fence)) {
          code.add(lines[i]);
          i++;
        }
        i++;
        out.add(_codeBlock(context, t, code.join('\n'), lang.isEmpty ? null : lang));
        continue;
      }
      final RegExpMatch? h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (h != null) {
        flushPara();
        final int level = h.group(1)!.length;
        final double size = switch (level) { 1 => fontSize * 1.9, 2 => fontSize * 1.5, 3 => fontSize * 1.25, _ => fontSize * 1.08 };
        out.add(Padding(
          padding: EdgeInsets.only(top: level <= 2 ? 14 : 8, bottom: 6),
          child: SelectableText.rich(_inline(t, h.group(2)!, level <= 2 ? serifText(t, size: size) : uiText(t, size: size, weight: FontWeight.w600))),
        ));
        if (level <= 2) out.add(Container(height: 1, color: t.border, margin: const EdgeInsets.only(bottom: 8)));
        i++;
        continue;
      }
      if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(trimmed)) {
        flushPara();
        out.add(Container(height: 1, color: t.border, margin: const EdgeInsets.symmetric(vertical: 12)));
        i++;
        continue;
      }
      if (trimmed.startsWith('>')) {
        flushPara();
        final List<String> quote = [];
        while (i < lines.length && lines[i].trimLeft().startsWith('>')) {
          quote.add(lines[i].trimLeft().substring(1).trimLeft());
          i++;
        }
        out.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: t.accent, width: 3)), color: t.accentSoft),
          child: SelectableText.rich(_inline(t, quote.join(' '), _base(t).copyWith(color: t.textMuted))),
        ));
        continue;
      }
      final RegExpMatch? li = RegExp(r'^(\s*)([-*+]|\d+[.)])\s+(\[[ xX]\]\s+)?(.*)$').firstMatch(line);
      if (li != null) {
        flushPara();
        final int depth = li.group(1)!.length ~/ 2;
        final String marker = li.group(2)!;
        final String? task = li.group(3);
        final bool ordered = RegExp(r'\d').hasMatch(marker);
        out.add(Padding(
          padding: EdgeInsets.only(left: 6.0 + depth * 18, top: 2, bottom: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 22,
              child: task != null
                  ? Icon(task.toLowerCase().contains('x') ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 16, color: t.accent)
                  : Text(ordered ? marker : '•', style: _base(t).copyWith(color: t.accent, fontWeight: FontWeight.w700)),
            ),
            Expanded(child: SelectableText.rich(_inline(t, li.group(4)!, _base(t)))),
          ]),
        ));
        i++;
        continue;
      }
      if (trimmed.startsWith('|') && i + 1 < lines.length && RegExp(r'^\s*\|?\s*:?-{2,}').hasMatch(lines[i + 1])) {
        flushPara();
        final List<List<String>> rows = [];
        while (i < lines.length && lines[i].trimLeft().startsWith('|')) {
          if (!RegExp(r'^\s*\|?\s*:?-{2,}').hasMatch(lines[i])) {
            rows.add(lines[i].trim().replaceAll(RegExp(r'^\||\|$'), '').split('|').map((c) => c.trim()).toList());
          }
          i++;
        }
        out.add(_table(t, rows));
        continue;
      }
      if (trimmed.isEmpty) {
        flushPara();
        i++;
        continue;
      }
      para.add(trimmed);
      i++;
    }
    flushPara();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }

  TextStyle _base(IdeTheme t) => uiText(t, size: fontSize, height: 1.6);

  Widget _block(Widget child) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: child);

  Widget _table(IdeTheme t, List<List<String>> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final int cols = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: t.border, borderRadius: BorderRadius.circular(6)),
          children: [
            for (int r = 0; r < rows.length; r++)
              TableRow(
                decoration: BoxDecoration(color: r == 0 ? t.hover : null),
                children: [
                  for (int c = 0; c < cols; c++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Text.rich(_inline(t, c < rows[r].length ? rows[r][c] : '', _base(t).copyWith(fontWeight: r == 0 ? FontWeight.w600 : null))),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _codeBlock(BuildContext context, IdeTheme t, String code, String? lang) {
    final TextStyle mono = TextStyle(fontFamily: 'JetBrains Mono', fontFamilyFallback: const ['Consolas', 'monospace'], fontSize: fontSize * 0.88, height: 1.5, color: t.text);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: t.isDark ? IdeTheme.shift(t.editorBg, -0.03) : IdeTheme.shift(t.editorBg, -0.025),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 30,
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
          child: Row(children: [
            Text(lang ?? 'text', style: uiText(t, size: 11.5, color: t.textMuted)),
            const Spacer(),
            ...?codeActions?.call(code, lang),
            IconBtn(icon: Icons.content_copy_rounded, size: 14, tooltip: 'Copy', onTap: () => copyToClipboard(context, code)),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: SelectableText.rich(highlightCode(code, lang, t, mono)),
        ),
      ]),
    );
  }

  static final RegExp _inlineRe = RegExp(r'(`[^`]+`)|(\*\*[^*]+\*\*)|(__[^_]+__)|(\*[^*\s][^*]*\*)|(_[^_\s][^_]*_)|(~~[^~]+~~)|(\[[^\]]+\]\([^)]+\))|(https?://[^\s)]+)');

  TextSpan _inline(IdeTheme t, String text, TextStyle base) {
    final List<InlineSpan> spans = [];
    int last = 0;
    for (final RegExpMatch m in _inlineRe.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final String s = m.group(0)!;
      if (m.group(1) != null) {
        spans.add(TextSpan(
          text: s.substring(1, s.length - 1),
          style: TextStyle(fontFamily: 'JetBrains Mono', fontSize: base.fontSize! * 0.9, color: t.accent, backgroundColor: t.accentSoft),
        ));
      } else if (m.group(2) != null || m.group(3) != null) {
        spans.add(TextSpan(children: [_inline(t, s.substring(2, s.length - 2), base)], style: const TextStyle(fontWeight: FontWeight.w700)));
      } else if (m.group(4) != null || m.group(5) != null) {
        spans.add(TextSpan(text: s.substring(1, s.length - 1), style: const TextStyle(fontStyle: FontStyle.italic)));
      } else if (m.group(6) != null) {
        spans.add(TextSpan(text: s.substring(2, s.length - 2), style: const TextStyle(decoration: TextDecoration.lineThrough)));
      } else if (m.group(7) != null) {
        final RegExpMatch lm = RegExp(r'\[([^\]]+)\]\(([^)]+)\)').firstMatch(s)!;
        final String url = lm.group(2)!;
        spans.add(TextSpan(
          text: lm.group(1),
          style: TextStyle(color: t.accent, decoration: TextDecoration.underline, decorationColor: t.accent.withValues(alpha: 0.5)),
          recognizer: TapGestureRecognizer()..onTap = () => LiveServer.openInBrowser(url),
        ));
      } else {
        spans.add(TextSpan(
          text: s,
          style: TextStyle(color: t.accent, decoration: TextDecoration.underline, decorationColor: t.accent.withValues(alpha: 0.5)),
          recognizer: TapGestureRecognizer()..onTap = () => LiveServer.openInBrowser(s),
        ));
      }
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return TextSpan(style: base, children: spans);
  }
}

/// Live preview of a Markdown file (follows unsaved edits).
class MarkdownPreviewPage extends StatelessWidget {
  const MarkdownPreviewPage({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final Workspace ws = context.watch<Workspace>();
    final EditorDocument? doc = ws.openDocuments.where((d) => d.path == path).firstOrNull;
    if (doc != null) {
      return SafeListenableBuilder(listenable: doc.controller, builder: (context) => _page(context, doc.text));
    }
    return FutureBuilder<String>(
      future: File(path).readAsString(),
      builder: (context, s) => _page(context, s.data ?? ''),
    );
  }

  Widget _page(BuildContext context, String text) {
    context.read<Ide>();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
      child: Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820), child: MarkdownBody(text: text, fontSize: 15)),
      ),
    );
  }
}
