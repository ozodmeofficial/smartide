import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../../theme/ide_theme.dart';
import '../widgets.dart';

/// VS Code style floating find / replace widget.
class FindPanel extends StatelessWidget implements PreferredSizeWidget {
  const FindPanel({super.key, required this.controller, required this.readOnly, required this.theme});

  final CodeFindController controller;
  final bool readOnly;
  final IdeTheme theme;

  @override
  Size get preferredSize => Size(double.infinity, controller.value == null ? 0 : (controller.value!.replaceMode ? 86 : 50));

  @override
  Widget build(BuildContext context) {
    final CodeFindValue? value = controller.value;
    if (value == null) return const SizedBox.shrink();
    final IdeTheme t = theme;
    final String count = value.result == null
        ? (value.option.pattern.isEmpty ? '' : 'No results')
        : '${value.result!.index + 1} of ${value.result!.matches.length}';
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 22, top: 6),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 430,
            padding: const EdgeInsets.fromLTRB(4, 5, 6, 5),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.border),
              boxShadow: [BoxShadow(color: t.shadow, blurRadius: 18, offset: const Offset(0, 6))],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconBtn(
                  icon: value.replaceMode ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                  tooltip: 'Toggle Replace',
                  box: 22,
                  onTap: readOnly ? null : controller.toggleMode,
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        Expanded(
                          child: _field(t, controller.findInputController, controller.findInputFocusNode, 'Find', [
                            ToggleGlyph(label: 'Aa', value: value.option.caseSensitive, onChanged: (_) => controller.toggleCaseSensitive(), tooltip: 'Match Case (Alt+C)'),
                            ToggleGlyph(label: '.*', value: value.option.regex, onChanged: (_) => controller.toggleRegex(), tooltip: 'Use Regular Expression (Alt+R)'),
                          ]),
                        ),
                        SizedBox(
                          width: 74,
                          child: Text(count,
                              textAlign: TextAlign.center,
                              style: uiText(t, size: 11.5, color: value.result == null && value.option.pattern.isNotEmpty ? t.error : t.textMuted)),
                        ),
                        IconBtn(icon: Icons.arrow_upward_rounded, box: 22, size: 15, tooltip: 'Previous Match (Shift+Enter)', onTap: value.result == null ? null : controller.previousMatch),
                        IconBtn(icon: Icons.arrow_downward_rounded, box: 22, size: 15, tooltip: 'Next Match (Enter)', onTap: value.result == null ? null : controller.nextMatch),
                        IconBtn(icon: Icons.close_rounded, box: 22, size: 15, tooltip: 'Close (Escape)', onTap: controller.close),
                      ]),
                      if (value.replaceMode) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          Expanded(child: _field(t, controller.replaceInputController, controller.replaceInputFocusNode, 'Replace', const [])),
                          const SizedBox(width: 6),
                          IconBtn(icon: Icons.find_replace_rounded, box: 22, size: 15, tooltip: 'Replace (Enter)', onTap: value.result == null ? null : controller.replaceMatch),
                          IconBtn(icon: Icons.done_all_rounded, box: 22, size: 15, tooltip: 'Replace All (Ctrl+Alt+Enter)', onTap: value.result == null ? null : controller.replaceAllMatches),
                          const SizedBox(width: 44),
                        ]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(IdeTheme t, TextEditingController c, FocusNode f, String hint, List<Widget> toggles) {
    return SizedBox(
      height: 30,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, shift: true): controller.previousMatch,
          const SingleActivator(LogicalKeyboardKey.keyC, alt: true): controller.toggleCaseSensitive,
          const SingleActivator(LogicalKeyboardKey.keyR, alt: true): controller.toggleRegex,
        },
        child: TextField(
          controller: c,
          focusNode: f,
          style: uiText(t, size: 13),
          cursorColor: t.accent,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            suffixIcon: toggles.isEmpty ? null : Row(mainAxisSize: MainAxisSize.min, children: [...toggles, const SizedBox(width: 4)]),
            suffixIconConstraints: const BoxConstraints(minHeight: 20),
          ),
        ),
      ),
    );
  }
}
