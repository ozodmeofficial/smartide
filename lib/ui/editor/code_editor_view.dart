import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';

import '../../app/ide.dart';
import '../../core/commands.dart';
import '../../core/settings.dart';
import '../../theme/fonts.dart';
import '../../theme/ide_theme.dart';
import '../../workspace/editor_document.dart';
import '../../workspace/workspace.dart';
import '../widgets.dart';
import 'autocomplete.dart';
import 'find_panel.dart';
import 'minimap.dart';

/// VS Code (Windows) keyboard layout for the editing surface.
class VsCodeShortcuts extends CodeShortcutsActivatorsBuilder {
  const VsCodeShortcuts();

  static const Map<CodeShortcutType, List<ShortcutActivator>> _map = {
    CodeShortcutType.selectAll: [SingleActivator(LogicalKeyboardKey.keyA, control: true)],
    CodeShortcutType.cut: [SingleActivator(LogicalKeyboardKey.keyX, control: true), SingleActivator(LogicalKeyboardKey.delete, shift: true)],
    CodeShortcutType.copy: [SingleActivator(LogicalKeyboardKey.keyC, control: true), SingleActivator(LogicalKeyboardKey.insert, control: true)],
    CodeShortcutType.paste: [SingleActivator(LogicalKeyboardKey.keyV, control: true), SingleActivator(LogicalKeyboardKey.insert, shift: true)],
    CodeShortcutType.delete: [SingleActivator(LogicalKeyboardKey.delete)],
    CodeShortcutType.backspace: [SingleActivator(LogicalKeyboardKey.backspace), SingleActivator(LogicalKeyboardKey.backspace, shift: true)],
    CodeShortcutType.undo: [SingleActivator(LogicalKeyboardKey.keyZ, control: true)],
    CodeShortcutType.redo: [SingleActivator(LogicalKeyboardKey.keyY, control: true), SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true)],
    CodeShortcutType.lineSelect: [SingleActivator(LogicalKeyboardKey.keyL, control: true)],
    CodeShortcutType.lineDelete: [SingleActivator(LogicalKeyboardKey.keyK, control: true, shift: true)],
    CodeShortcutType.lineMoveUp: [SingleActivator(LogicalKeyboardKey.arrowUp, alt: true)],
    CodeShortcutType.lineMoveDown: [SingleActivator(LogicalKeyboardKey.arrowDown, alt: true)],
    CodeShortcutType.cursorMoveUp: [SingleActivator(LogicalKeyboardKey.arrowUp)],
    CodeShortcutType.cursorMoveDown: [SingleActivator(LogicalKeyboardKey.arrowDown)],
    CodeShortcutType.cursorMoveForward: [SingleActivator(LogicalKeyboardKey.arrowRight)],
    CodeShortcutType.cursorMoveBackward: [SingleActivator(LogicalKeyboardKey.arrowLeft)],
    CodeShortcutType.cursorMoveLineStart: [SingleActivator(LogicalKeyboardKey.home)],
    CodeShortcutType.cursorMoveLineEnd: [SingleActivator(LogicalKeyboardKey.end)],
    CodeShortcutType.cursorMovePageStart: [SingleActivator(LogicalKeyboardKey.home, control: true)],
    CodeShortcutType.cursorMovePageEnd: [SingleActivator(LogicalKeyboardKey.end, control: true)],
    CodeShortcutType.cursorMovePageUp: [SingleActivator(LogicalKeyboardKey.pageUp)],
    CodeShortcutType.cursorMovePageDown: [SingleActivator(LogicalKeyboardKey.pageDown)],
    CodeShortcutType.cursorMoveWordBoundaryForward: [SingleActivator(LogicalKeyboardKey.arrowRight, control: true)],
    CodeShortcutType.cursorMoveWordBoundaryBackward: [SingleActivator(LogicalKeyboardKey.arrowLeft, control: true)],
    CodeShortcutType.selectionExtendUp: [SingleActivator(LogicalKeyboardKey.arrowUp, shift: true)],
    CodeShortcutType.selectionExtendDown: [SingleActivator(LogicalKeyboardKey.arrowDown, shift: true)],
    CodeShortcutType.selectionExtendForward: [SingleActivator(LogicalKeyboardKey.arrowRight, shift: true)],
    CodeShortcutType.selectionExtendBackward: [SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true)],
    CodeShortcutType.selectionExtendLineStart: [SingleActivator(LogicalKeyboardKey.home, shift: true)],
    CodeShortcutType.selectionExtendLineEnd: [SingleActivator(LogicalKeyboardKey.end, shift: true)],
    CodeShortcutType.selectionExtendPageStart: [SingleActivator(LogicalKeyboardKey.home, shift: true, control: true)],
    CodeShortcutType.selectionExtendPageEnd: [SingleActivator(LogicalKeyboardKey.end, shift: true, control: true)],
    CodeShortcutType.selectionExtendWordBoundaryForward: [SingleActivator(LogicalKeyboardKey.arrowRight, shift: true, control: true)],
    CodeShortcutType.selectionExtendWordBoundaryBackward: [SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true, control: true)],
    CodeShortcutType.wordDeleteForward: [SingleActivator(LogicalKeyboardKey.delete, control: true)],
    CodeShortcutType.wordDeleteBackward: [SingleActivator(LogicalKeyboardKey.backspace, control: true)],
    CodeShortcutType.indent: [SingleActivator(LogicalKeyboardKey.tab)],
    CodeShortcutType.outdent: [SingleActivator(LogicalKeyboardKey.tab, shift: true)],
    CodeShortcutType.newLine: [SingleActivator(LogicalKeyboardKey.enter), SingleActivator(LogicalKeyboardKey.numpadEnter), SingleActivator(LogicalKeyboardKey.enter, shift: true)],
    CodeShortcutType.singleLineComment: [SingleActivator(LogicalKeyboardKey.slash, control: true), SingleActivator(LogicalKeyboardKey.numpadDivide, control: true)],
    CodeShortcutType.multiLineComment: [SingleActivator(LogicalKeyboardKey.keyA, shift: true, alt: true)],
    CodeShortcutType.find: [SingleActivator(LogicalKeyboardKey.keyF, control: true)],
    CodeShortcutType.findToggleMatchCase: [SingleActivator(LogicalKeyboardKey.keyC, alt: true)],
    CodeShortcutType.findToggleRegex: [SingleActivator(LogicalKeyboardKey.keyR, alt: true)],
    CodeShortcutType.replace: [SingleActivator(LogicalKeyboardKey.keyH, control: true)],
    CodeShortcutType.esc: [SingleActivator(LogicalKeyboardKey.escape)],
  };

  @override
  List<ShortcutActivator>? build(CodeShortcutType type) => _map[type];
}

/// Comment toggling that respects each language's comment tokens.
class LanguageCommentFormatter implements CodeCommentFormatter {
  LanguageCommentFormatter(this.doc);

  final EditorDocument doc;

  @override
  CodeLineEditingValue format(CodeLineEditingValue value, String indent, bool single) {
    final String? line = doc.language.lineComment;
    final (String, String)? block = doc.language.blockComment;
    if (single && line != null) {
      return DefaultCodeCommentFormatter(singleLinePrefix: line, multiLinePrefix: block?.$1 ?? line, multiLineSuffix: block?.$2 ?? '').format(value, indent, true);
    }
    if (block != null) {
      return DefaultCodeCommentFormatter(singleLinePrefix: line ?? block.$1, multiLinePrefix: block.$1, multiLineSuffix: block.$2).format(value, indent, false);
    }
    return value;
  }
}

class _EditorContextMenu implements SelectionToolbarController {
  _EditorContextMenu(this.ide);

  final Ide ide;

  @override
  void hide(BuildContext context) {}

  @override
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
  }) {
    final CommandRegistry c = ide.commands;
    final bool hasLsp = ide.workspace.activeDocument != null && ide.lsp.clientFor(ide.workspace.activeDocument!) != null;
    showContextMenu(context, anchors.primaryAnchor, [
      MenuEntry('Go to Definition', icon: Icons.call_made_rounded, shortcut: c.shortcutFor('editor.action.revealDefinition'), onTap: hasLsp ? ide.goToDefinition : null),
      MenuEntry('Format Document', icon: Icons.auto_fix_high_rounded, shortcut: c.shortcutFor('editor.action.formatDocument'), onTap: ide.formatDocument),
      MenuEntry('Change All Occurrences', icon: Icons.select_all_rounded, shortcut: 'Ctrl+D', onTap: ide.selectNextOccurrence),
      const MenuEntry.divider(),
      MenuEntry('Cut', icon: Icons.content_cut_rounded, shortcut: 'Ctrl+X', onTap: controller.cut),
      MenuEntry('Copy', icon: Icons.content_copy_rounded, shortcut: 'Ctrl+C', onTap: controller.copy),
      MenuEntry('Paste', icon: Icons.content_paste_rounded, shortcut: 'Ctrl+V', onTap: controller.paste),
      const MenuEntry.divider(),
      if (ide.extensions.isEnabled('smartide.assistant'))
        MenuEntry('Ask Assistant about Selection', icon: Icons.auto_awesome_rounded, onTap: () {
          ide.assistantVisible = true;
          ide.touch();
        }),
      MenuEntry('Run File', icon: Icons.play_arrow_rounded, shortcut: 'F5', onTap: ide.runActiveFile),
      MenuEntry('Command Palette…', icon: Icons.keyboard_command_key_rounded, shortcut: 'Ctrl+Shift+P', onTap: ide.showCommandPalette),
    ]);
  }
}

class CodeEditorView extends StatefulWidget {
  const CodeEditorView({super.key, required this.doc, required this.active});

  final EditorDocument doc;
  final bool active;

  @override
  State<CodeEditorView> createState() => _CodeEditorViewState();
}

class _CodeEditorViewState extends State<CodeEditorView> {
  late IdePromptsBuilder _prompts;
  late _EditorContextMenu _menu;
  Map<int, List<Diagnostic>> _diagByLine = {};
  List<Diagnostic>? _lastDiags;

  static final RegExp _todo = RegExp(r'\b(TODO|FIXME|HACK|NOTE|XXX|BUG)\b:?');

  @override
  void initState() {
    super.initState();
    final Ide ide = context.read<Ide>();
    _prompts = IdePromptsBuilder(ide: ide, doc: widget.doc);
    _menu = _EditorContextMenu(ide);
    widget.doc.spanDecorator = _decorate;
  }

  @override
  void didUpdateWidget(covariant CodeEditorView old) {
    super.didUpdateWidget(old);
    if (old.doc != widget.doc) {
      _prompts = IdePromptsBuilder(ide: context.read<Ide>(), doc: widget.doc);
      widget.doc.spanDecorator = _decorate;
      _lastDiags = null;
    }
  }

  void _syncDiagnostics(Workspace ws) {
    final List<Diagnostic>? diags = widget.doc.path == null ? null : ws.diagnostics[widget.doc.path];
    if (identical(diags, _lastDiags)) return;
    _lastDiags = diags;
    final Map<int, List<Diagnostic>> map = {};
    for (final Diagnostic d in diags ?? const []) {
      map.putIfAbsent(d.line, () => []).add(d);
    }
    _diagByLine = map;
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.doc.controller.forceRepaint());
  }

  TextSpan _decorate(int index, String line, TextSpan span, TextStyle style) {
    final Ide ide = context.read<Ide>();
    final IdeTheme t = ide.effectiveTheme;
    final List<(int, int, TextStyle)> ranges = [];
    final List<Diagnostic>? diags = _diagByLine[index];
    if (diags != null) {
      for (final Diagnostic d in diags) {
        int start = d.column.clamp(0, line.length);
        int end = (d.endLine == d.line ? (d.endColumn ?? d.column + 1) : line.length).clamp(start, line.length);
        if (end == start) {
          // Zero-width diagnostics underline the word at that position.
          end = (start + 1).clamp(0, line.length);
          if (end == start && start > 0) start--;
        }
        final Color c = switch (d.severity) {
          DiagnosticSeverity.error => t.error,
          DiagnosticSeverity.warning => t.warning,
          DiagnosticSeverity.info => t.info,
          DiagnosticSeverity.hint => t.textFaint,
        };
        ranges.add((start, end, TextStyle(decoration: TextDecoration.underline, decorationStyle: TextDecorationStyle.wavy, decorationColor: c, decorationThickness: 1.4)));
      }
    }
    if (ide.extensions.isEnabled('smartide.todo') && line.length < 2000) {
      for (final RegExpMatch m in _todo.allMatches(line)) {
        final String? lc = widget.doc.language.lineComment;
        final String before = line.substring(0, m.start);
        if (lc != null && !before.contains(lc) && !before.contains('/*') && !before.trimLeft().startsWith('*')) continue;
        ranges.add((m.start, m.end, TextStyle(backgroundColor: t.warning.withValues(alpha: 0.22), color: t.warning, fontWeight: FontWeight.w700)));
      }
    }
    final bool noLigatures = !ide.settings.ligatures;
    if (ranges.isEmpty && !noLigatures) return span;
    final TextSpan out = ranges.isEmpty ? span : applyRanges(span, ranges);
    if (!noLigatures) return out;
    return TextSpan(style: const TextStyle(fontFeatures: [FontFeature.disable('liga'), FontFeature.disable('calt')]), children: [out]);
  }

  @override
  Widget build(BuildContext context) {
    final Ide ide = context.watch<Ide>();
    final Settings s = ide.settings;
    final IdeTheme t = ide.effectiveTheme;
    final EditorDocument doc = widget.doc;
    final Workspace ws = context.watch<Workspace>();
    context.watch<FontManager>();
    _syncDiagnostics(ws);
    final String family = ide.fonts.isLoaded(s.editorFont) ? s.editorFont : 'JetBrains Mono';
    final double lineH = s.editorFontSize * s.lineHeight;

    final Map<int, Color> markers = {
      for (final MapEntry<int, List<Diagnostic>> e in _diagByLine.entries)
        e.key: e.value.any((d) => d.severity == DiagnosticSeverity.error) ? t.error : t.warning,
    };

    final Widget editor = CodeAutocomplete(
      viewBuilder: (context, notifier, onSelected) => SuggestList(notifier: notifier, onSelected: onSelected, theme: t, fontFamily: family),
      promptsBuilder: _prompts,
      child: CodeEditor(
        key: ValueKey(doc.id),
        controller: doc.controller,
        findController: doc.findController,
        scrollController: doc.scrollController,
        focusNode: doc.focusNode,
        autofocus: widget.active,
        readOnly: doc.readOnly,
        wordWrap: s.wordWrap,
        autocompleteSymbols: s.autoClosingBrackets,
        toolbarController: _menu,
        commentFormatter: LanguageCommentFormatter(doc),
        shortcutsActivatorsBuilder: const VsCodeShortcuts(),
        padding: const EdgeInsets.only(left: 4, top: 6, bottom: 120, right: 16),
        verticalScrollbarWidth: 10,
        horizontalScrollbarHeight: 10,
        scrollbarBuilder: (context, child, details) => Scrollbar(
          controller: details.controller,
          thickness: 8,
          radius: const Radius.circular(8),
          child: child,
        ),
        style: CodeEditorStyle(
          fontSize: s.editorFontSize,
          fontFamily: family,
          fontFamilyFallback: FontManager.fallback,
          fontHeight: s.lineHeight,
          textColor: t.text,
          hintTextColor: t.textFaint,
          backgroundColor: t.editorBg,
          selectionColor: t.selection,
          highlightColor: t.accent.withValues(alpha: 0.22),
          cursorColor: t.accent,
          cursorWidth: 2,
          cursorLineColor: s.highlightActiveLine ? t.lineHighlight : null,
          chunkIndicatorColor: t.textFaint,
          codeTheme: CodeHighlightTheme(
            languages: {doc.language.id: CodeHighlightThemeMode(mode: doc.language.mode)},
            theme: t.syntax,
          ),
        ),
        indicatorBuilder: (context, editingController, chunkController, notifier) {
          return Row(
            children: [
              _DiagnosticGutter(notifier: notifier, diagnostics: _diagByLine, theme: t),
              if (s.lineNumbers)
                DefaultCodeLineNumber(
                  controller: editingController,
                  notifier: notifier,
                  textStyle: TextStyle(color: t.textFaint, fontSize: s.editorFontSize * 0.9, fontFamily: family, fontFamilyFallback: FontManager.fallback),
                  focusedTextStyle: TextStyle(color: t.text, fontSize: s.editorFontSize * 0.9, fontFamily: family, fontFamilyFallback: FontManager.fallback),
                ),
              DefaultCodeChunkIndicator(width: 18, controller: chunkController, notifier: notifier),
            ],
          );
        },
        findBuilder: (context, controller, readOnly) => FindPanel(controller: controller, readOnly: readOnly, theme: t),
      ),
    );

    if (!s.minimap) return editor;
    return Row(
      children: [
        Expanded(child: editor),
        SizedBox(
          width: 84,
          child: DecoratedBox(
            decoration: BoxDecoration(border: Border(left: BorderSide(color: t.border.withValues(alpha: 0.5)))),
            child: Minimap(controller: doc.controller, scroll: doc.scrollController.verticalScroller, theme: t, lineHeight: lineH, markers: markers),
          ),
        ),
      ],
    );
  }
}

/// Coloured dots next to lines that have diagnostics. Painted (not built)
/// because the indicator notifier fires during layout.
class _DiagnosticGutter extends StatelessWidget {
  const _DiagnosticGutter({required this.notifier, required this.diagnostics, required this.theme});

  final CodeIndicatorValueNotifier notifier;
  final Map<int, List<Diagnostic>> diagnostics;
  final IdeTheme theme;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      child: CustomPaint(painter: _GutterPainter(notifier, diagnostics, theme), size: Size.infinite),
    );
  }
}

class _GutterPainter extends CustomPainter {
  _GutterPainter(this.notifier, this.diagnostics, this.theme) : super(repaint: notifier);

  final CodeIndicatorValueNotifier notifier;
  final Map<int, List<Diagnostic>> diagnostics;
  final IdeTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final CodeIndicatorValue? value = notifier.value;
    if (value == null || diagnostics.isEmpty) return;
    final Paint paint = Paint();
    for (final CodeLineRenderParagraph p in value.paragraphs) {
      final List<Diagnostic>? d = diagnostics[p.index];
      if (d == null) continue;
      paint.color = d.any((x) => x.severity == DiagnosticSeverity.error) ? theme.error : theme.warning;
      canvas.drawCircle(Offset(8, p.top + p.preferredLineHeight / 2), 3.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GutterPainter old) => old.diagnostics != diagnostics || old.theme != theme;
}

/// Re-styles character ranges of a (possibly nested) highlighted [TextSpan].
TextSpan applyRanges(TextSpan root, List<(int, int, TextStyle)> ranges) {
  final List<(String, TextStyle?)> leaves = [];
  void walk(InlineSpan span, TextStyle? inherited) {
    if (span is! TextSpan) return;
    final TextStyle? style = inherited == null ? span.style : (span.style == null ? inherited : inherited.merge(span.style));
    if (span.text != null && span.text!.isNotEmpty) leaves.add((span.text!, style));
    for (final InlineSpan c in span.children ?? const <InlineSpan>[]) {
      walk(c, style);
    }
  }

  walk(root, null);
  final Set<int> cuts = {0};
  for (final (int s, int e, TextStyle _) in ranges) {
    cuts
      ..add(s)
      ..add(e);
  }
  final List<TextSpan> out = [];
  int pos = 0;
  for (final (String text, TextStyle? style) in leaves) {
    final int end = pos + text.length;
    final List<int> points = [pos, ...cuts.where((c) => c > pos && c < end).toList()..sort(), end];
    for (int i = 0; i < points.length - 1; i++) {
      final int a = points[i], b = points[i + 1];
      TextStyle? st = style;
      for (final (int s, int e, TextStyle overlay) in ranges) {
        if (a >= s && b <= e) st = st == null ? overlay : st.merge(overlay);
      }
      out.add(TextSpan(text: text.substring(a - pos, b - pos), style: st));
    }
    pos = end;
  }
  return TextSpan(style: root.style, children: out);
}
