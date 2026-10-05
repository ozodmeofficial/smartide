import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';

import '../app/ide.dart';
import '../services/assistant_service.dart';
import '../services/live_server.dart';
import '../theme/ide_theme.dart';
import '../workspace/editor_document.dart';
import 'logo.dart';
import 'pages/markdown_view.dart';
import 'widgets.dart';

class AssistantPanel extends StatefulWidget {
  const AssistantPanel({super.key});

  @override
  State<AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends State<AssistantPanel> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  bool _attach = true;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  (String?, String?, String?) _context(Ide ide) {
    if (!_attach) return (null, null, null);
    final EditorDocument? d = ide.workspace.activeDocument;
    if (d == null) return (null, null, null);
    final CodeLineSelection s = d.controller.selection;
    if (!s.isCollapsed) {
      return ('${d.title} · lines ${s.start.index + 1}-${s.end.index + 1}', d.controller.selectedText, d.language.id);
    }
    String text = d.text;
    if (text.length > 120000) text = '${text.substring(0, 120000)}\n…(truncated)';
    return (d.title, text, d.language.id);
  }

  Future<void> _send(Ide ide, [String? preset]) async {
    final String prompt = preset ?? _input.text.trim();
    if (prompt.isEmpty) return;
    final (String? label, String? code, String? lang) = _context(ide);
    _input.clear();
    final Future<void> f = ide.assistant.send(prompt, contextLabel: label, contextCode: code, language: lang);
    _scrollToEnd();
    await f;
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  void _insert(Ide ide, String code) {
    final EditorDocument? d = ide.workspace.activeDocument;
    if (d == null) {
      ide.workspace.newUntitled(text: code);
      return;
    }
    d.controller.replaceSelection(code);
    ide.focusEditor();
  }

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Ide ide = context.watch<Ide>();
    final AssistantService a = context.watch<AssistantService>();
    if (a.busy) _scrollToEnd();
    final (String? ctxLabel, _, _) = _context(ide);
    return Card2(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
          child: Row(children: [
            const SmartIdeLogo(size: 18),
            const SizedBox(width: 8),
            Text('Assistant', style: serifText(t, size: 16)),
            const SizedBox(width: 8),
            HoverBox(
              radius: 6,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              tooltip: 'Change model',
              onTap: () {
                final RenderBox box = context.findRenderObject()! as RenderBox;
                showContextMenu(context, box.localToGlobal(const Offset(60, 40)), [
                  for (final AssistantModel m in assistantModels)
                    MenuEntry('${m.name}  ·  ${m.note}', icon: m.id == a.model.id ? Icons.check_rounded : null, onTap: () => ide.settings.update((s) => s.aiModel = m.id)),
                ]);
              },
              child: Row(children: [
                Text(a.model.name, style: uiText(t, size: 11.5, color: t.textMuted)),
                Icon(Icons.expand_more_rounded, size: 14, color: t.textMuted),
              ]),
            ),
            const Spacer(),
            IconBtn(icon: Icons.add_comment_outlined, size: 16, tooltip: 'New Chat', onTap: a.clear),
            IconBtn(icon: Icons.close_rounded, size: 16, tooltip: 'Close', onTap: ide.toggleAssistant),
          ]),
        ),
        Expanded(
          child: !a.hasKey
              ? _Onboarding(ide: ide)
              : a.messages.isEmpty
                  ? _Empty(onPick: (p) => _send(ide, p))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
                      itemCount: a.messages.length,
                      itemBuilder: (context, i) => _Message(msg: a.messages[i], onInsert: (c) => _insert(ide, c)),
                    ),
        ),
        if (a.hasKey)
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: t.border))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                HoverBox(
                  radius: 6,
                  onTap: () => setState(() => _attach = !_attach),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Row(children: [
                    Icon(_attach ? Icons.attach_file_rounded : Icons.link_off_rounded, size: 13, color: _attach && ctxLabel != null ? t.accent : t.textFaint),
                    const SizedBox(width: 4),
                    Text(_attach ? (ctxLabel ?? 'No file open') : 'Context off', style: uiText(t, size: 11.5, color: _attach && ctxLabel != null ? t.accent : t.textFaint)),
                  ]),
                ),
              ]),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(color: t.inputBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: t.border)),
                padding: const EdgeInsets.fromLTRB(12, 4, 6, 6),
                child: Column(children: [
                  CallbackShortcuts(
                    bindings: {const SingleActivator(LogicalKeyboardKey.enter): () => _send(ide)},
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 8,
                      style: uiText(t, size: 13.5),
                      cursorColor: t.accent,
                      decoration: const InputDecoration(
                        hintText: 'Ask about your code…  (Enter to send, Shift+Enter for new line)',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  Row(children: [
                    const Spacer(),
                    if (a.busy)
                      HoverBox(
                        onTap: a.cancel,
                        radius: 8,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(color: t.hover, borderRadius: BorderRadius.circular(8)),
                          child: Icon(Icons.stop_rounded, size: 18, color: t.text),
                        ),
                      )
                    else
                      HoverBox(
                        onTap: () => _send(ide),
                        radius: 8,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(8)),
                          child: Icon(Icons.arrow_upward_rounded, size: 18, color: t.onAccent),
                        ),
                      ),
                  ]),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.msg, required this.onInsert});

  final ChatMessage msg;
  final ValueChanged<String> onInsert;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    if (msg.role == 'user') {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(left: 40, bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: t.accentSoft, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            SelectableText(msg.text, style: uiText(t, size: 13.5, height: 1.45)),
            if (msg.context != null) ...[
              const SizedBox(height: 4),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.attach_file_rounded, size: 11, color: t.textFaint),
                Text(msg.context!, style: uiText(t, size: 11, color: t.textFaint)),
              ]),
            ],
          ]),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 3), child: SmartIdeLogo(size: msg.streaming ? 18 : 16)),
        const SizedBox(width: 10),
        Expanded(
          child: msg.error
              ? Text(msg.text, style: uiText(t, size: 13, color: t.error))
              : msg.text.isEmpty && msg.streaming
                  ? Padding(padding: const EdgeInsets.only(top: 4), child: _Typing(color: t.accent))
                  : MarkdownBody(
                      text: msg.text,
                      fontSize: 13.5,
                      codeActions: (code, lang) => [
                        IconBtn(icon: Icons.input_rounded, size: 14, tooltip: 'Insert at Cursor', onTap: () => onInsert(code)),
                      ],
                    ),
        ),
      ]),
    );
  }
}

class _Typing extends StatefulWidget {
  const _Typing({required this.color});

  final Color color;

  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (int i = 0; i < 3; i++)
          Container(
            margin: const EdgeInsets.only(right: 4),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.3 + 0.7 * (((_c.value * 3 - i) % 3) < 1 ? 1 : 0)),
              shape: BoxShape.circle,
            ),
          ),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    const List<(IconData, String)> prompts = [
      (Icons.lightbulb_outline_rounded, 'Explain this code step by step'),
      (Icons.bug_report_outlined, 'Find bugs and suggest fixes'),
      (Icons.speed_rounded, 'How can I make this faster?'),
      (Icons.science_outlined, 'Write unit tests for this file'),
      (Icons.notes_rounded, 'Add clear comments and docstrings'),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 20),
        const SmartIdeLogo(size: 36),
        const SizedBox(height: 14),
        Text('How can I help?', style: serifText(t, size: 24)),
        const SizedBox(height: 6),
        Text('I can see your active file (or selection). Ask anything.', style: uiText(t, color: t.textMuted)),
        const SizedBox(height: 20),
        for (final (IconData icon, String p) in prompts)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: HoverBox(
              onTap: () => onPick(p),
              radius: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: t.border)),
                child: Row(children: [
                  Icon(icon, size: 16, color: t.accent),
                  const SizedBox(width: 10),
                  Expanded(child: Text(p, style: uiText(t, size: 13))),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class _Onboarding extends StatefulWidget {
  const _Onboarding({required this.ide});

  final Ide ide;

  @override
  State<_Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<_Onboarding> {
  final TextEditingController _key = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 16),
        const SmartIdeLogo(size: 40),
        const SizedBox(height: 14),
        Text('Pair program with Claude', style: serifText(t, size: 24)),
        const SizedBox(height: 8),
        Text('Paste an Anthropic API key to enable the assistant. The key stays on this computer in your SmartIDE settings.', style: uiText(t, color: t.textMuted, height: 1.5)),
        const SizedBox(height: 18),
        IdeTextField(controller: _key, hint: 'sk-ant-…', obscure: true),
        const SizedBox(height: 10),
        Row(children: [
          AccentButton(label: 'Save key', icon: Icons.key_rounded, onTap: () {
            if (_key.text.trim().isEmpty) return;
            widget.ide.settings.update((s) => s.aiApiKey = _key.text.trim());
          }),
          const SizedBox(width: 8),
          AccentButton(label: 'Get a key', subtle: true, icon: Icons.open_in_new_rounded, onTap: () => LiveServer.openInBrowser('https://console.anthropic.com/settings/keys')),
        ]),
      ]),
    );
  }
}
