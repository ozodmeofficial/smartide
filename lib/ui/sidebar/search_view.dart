import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../app/ide.dart';
import '../../services/search_service.dart';
import '../../theme/ide_theme.dart';
import '../widgets.dart';

class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final TextEditingController _q = TextEditingController();
  final TextEditingController _r = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _replace = false;
  bool _details = false;
  Timer? _debounce;
  late final Ide _ide;

  @override
  void initState() {
    super.initState();
    _ide = context.read<Ide>();
    _q.text = _ide.search.query;
    _r.text = _ide.search.replacement;
    _ide.searchFocusRequest.addListener(_focusInput);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusInput());
  }

  void _focusInput() {
    // Prefill with the editor selection, like VS Code.
    final String? sel = _ide.workspace.activeDocument?.controller.selectedText;
    if (sel != null && sel.isNotEmpty && !sel.contains('\n')) {
      _q.text = sel;
      _run();
    }
    _focus.requestFocus();
    _q.selection = TextSelection(baseOffset: 0, extentOffset: _q.text.length);
  }

  @override
  void dispose() {
    _ide.searchFocusRequest.removeListener(_focusInput);
    _debounce?.cancel();
    _q.dispose();
    _r.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _run() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      final SearchService s = _ide.search;
      s.query = _q.text;
      s.search();
    });
  }

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final SearchService s = context.watch<SearchService>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PaneHeader(title: 'Search', actions: [
        IconBtn(icon: Icons.refresh_rounded, size: 15, tooltip: 'Refresh', onTap: s.search),
        IconBtn(icon: Icons.clear_all_rounded, size: 15, tooltip: 'Clear Search Results', onTap: () {
          _q.clear();
          s.query = '';
          s.search();
        }),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 0, 10, 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconBtn(icon: _replace ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded, box: 22, tooltip: 'Toggle Replace', onTap: () => setState(() => _replace = !_replace)),
          const SizedBox(width: 2),
          Expanded(
            child: Column(children: [
              IdeTextField(
                controller: _q,
                focusNode: _focus,
                hint: 'Search',
                onChanged: (_) => _run(),
                onSubmitted: (_) => s.search(),
                suffix: Row(mainAxisSize: MainAxisSize.min, children: [
                  ToggleGlyph(label: 'Aa', value: s.caseSensitive, tooltip: 'Match Case', onChanged: (v) {
                    s.caseSensitive = v;
                    s.search();
                  }),
                  ToggleGlyph(label: 'ab', value: s.wholeWord, tooltip: 'Match Whole Word', onChanged: (v) {
                    s.wholeWord = v;
                    s.search();
                  }),
                  ToggleGlyph(label: '.*', value: s.regex, tooltip: 'Use Regular Expression', onChanged: (v) {
                    s.regex = v;
                    s.search();
                  }),
                  const SizedBox(width: 4),
                ]),
              ),
              if (_replace) ...[
                const SizedBox(height: 6),
                IdeTextField(
                  controller: _r,
                  hint: 'Replace',
                  onChanged: (v) => s.replacement = v,
                  suffix: IconBtn(
                    icon: Icons.done_all_rounded,
                    size: 15,
                    box: 22,
                    tooltip: 'Replace All',
                    onTap: s.results.isEmpty
                        ? null
                        : () async {
                            final int n = await s.replaceAll();
                            _ide.notifications.success('Replaced $n occurrence${n == 1 ? '' : 's'}');
                          },
                  ),
                ),
              ],
            ]),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 30, right: 10),
        child: Row(children: [
          Expanded(
            child: Text(
              s.error ?? (s.query.isEmpty ? '' : '${s.totalMatches} results in ${s.results.length} files${s.searching ? '…' : ''}'),
              style: uiText(t, size: 11.5, color: s.error != null ? t.error : t.textMuted),
            ),
          ),
          IconBtn(icon: Icons.more_horiz_rounded, size: 15, box: 22, tooltip: 'Toggle Search Details', active: _details, onTap: () => setState(() => _details = !_details)),
        ]),
      ),
      if (_details)
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 4, 10, 4),
          child: Column(children: [
            IdeTextField(hint: 'files to include (e.g. *.py, src/)', onChanged: (v) {
              s.include = v;
              _run();
            }),
            const SizedBox(height: 6),
            IdeTextField(hint: 'files to exclude', onChanged: (v) {
              s.exclude = v;
              _run();
            }),
          ]),
        ),
      if (s.searching) LinearProgressIndicator(minHeight: 2, color: t.accent, backgroundColor: Colors.transparent),
      const SizedBox(height: 4),
      Expanded(
        child: ListView.builder(
          itemCount: s.results.length,
          padding: const EdgeInsets.only(bottom: 24),
          itemBuilder: (context, i) => _FileResult(fm: s.results[i], query: s),
        ),
      ),
    ]);
  }
}

class _FileResult extends StatefulWidget {
  const _FileResult({required this.fm, required this.query});

  final FileMatches fm;
  final SearchService query;

  @override
  State<_FileResult> createState() => _FileResultState();
}

class _FileResultState extends State<_FileResult> {
  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Ide ide = context.read<Ide>();
    final FileMatches fm = widget.fm;
    final String rel = ide.workspace.relative(p.dirname(fm.path));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: HoverBox(
          radius: 6,
          onTap: () => setState(() => fm.collapsed = !fm.collapsed),
          child: SizedBox(
            height: 24,
            child: Row(children: [
              Icon(fm.collapsed ? Icons.chevron_right_rounded : Icons.keyboard_arrow_down_rounded, size: 16, color: t.textMuted),
              const SizedBox(width: 2),
              FileBadge(path: fm.path, size: 14),
              const SizedBox(width: 6),
              Text(p.basename(fm.path), style: uiText(t, size: 12.5, weight: FontWeight.w500)),
              const SizedBox(width: 6),
              Expanded(child: Text(rel == '.' ? '' : rel, style: uiText(t, size: 11, color: t.textFaint), overflow: TextOverflow.ellipsis)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: t.hover, borderRadius: BorderRadius.circular(8)),
                child: Text('${fm.matches.length}', style: uiText(t, size: 10.5, color: t.textMuted)),
              ),
              IconBtn(icon: Icons.close_rounded, size: 13, box: 20, tooltip: 'Dismiss', onTap: () => widget.query.dismiss(fm)),
              const SizedBox(width: 4),
            ]),
          ),
        ),
      ),
      if (!fm.collapsed)
        for (final SearchMatch m in fm.matches.take(200))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: HoverBox(
              radius: 6,
              onTap: () => ide.workspace.openFile(fm.path, line: m.line + 1, column: m.start + 1, preview: true),
              child: SizedBox(
                height: 22,
                child: Row(children: [
                  const SizedBox(width: 36),
                  Expanded(child: _preview(t, m)),
                  SizedBox(width: 34, child: Text('${m.line + 1}', textAlign: TextAlign.right, style: uiText(t, size: 10.5, color: t.textFaint))),
                  const SizedBox(width: 8),
                ]),
              ),
            ),
          ),
    ]);
  }

  Widget _preview(IdeTheme t, SearchMatch m) {
    final String line = m.preview;
    final int s = m.start.clamp(0, line.length);
    final int e = m.end.clamp(s, line.length);
    final int from = (s - 24).clamp(0, s);
    final String before = (from > 0 ? '…' : '') + line.substring(from, s).trimLeft();
    final bool replacing = widget.query.replacement.isNotEmpty;
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: uiText(t, size: 12.5, color: t.textMuted), children: [
        TextSpan(text: before),
        TextSpan(
          text: line.substring(s, e),
          style: TextStyle(
            color: t.text,
            backgroundColor: replacing ? t.error.withValues(alpha: 0.2) : t.accent.withValues(alpha: 0.25),
            decoration: replacing ? TextDecoration.lineThrough : null,
          ),
        ),
        if (replacing) TextSpan(text: widget.query.replacement, style: TextStyle(color: t.text, backgroundColor: t.success.withValues(alpha: 0.25))),
        TextSpan(text: line.substring(e)),
      ]),
    );
  }
}
