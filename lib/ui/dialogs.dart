import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/ide.dart';
import '../theme/ide_theme.dart';
import 'widgets.dart';

enum SaveChoice { save, discard, cancel }

Widget _dialogShell(BuildContext context, {required Widget child, double width = 440}) {
  final IdeTheme t = context.read<Ide>().effectiveTheme;
  return Dialog(
    backgroundColor: t.surface,
    elevation: 0,
    insetPadding: const EdgeInsets.all(24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: t.border)),
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Padding(padding: const EdgeInsets.fromLTRB(22, 20, 22, 18), child: child),
    ),
  );
}

Future<SaveChoice> showSaveChoice(BuildContext context, String name) async {
  final SaveChoice? r = await showDialog<SaveChoice>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) {
      final IdeTheme t = ctx.read<Ide>().effectiveTheme;
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(ctx, SaveChoice.cancel),
          const SingleActivator(LogicalKeyboardKey.enter): () => Navigator.pop(ctx, SaveChoice.save),
        },
        child: Focus(
          autofocus: true,
          child: _dialogShell(
            ctx,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.warning_amber_rounded, color: t.warning, size: 22),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Save changes to $name?', style: uiText(t, size: 15, weight: FontWeight.w600))),
                ]),
                const SizedBox(height: 10),
                Text("Your changes will be lost if you don't save them.", style: uiText(t, color: t.textMuted)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AccentButton(label: 'Cancel', subtle: true, onTap: () => Navigator.pop(ctx, SaveChoice.cancel)),
                    const SizedBox(width: 8),
                    AccentButton(label: "Don't Save", subtle: true, onTap: () => Navigator.pop(ctx, SaveChoice.discard)),
                    const SizedBox(width: 8),
                    AccentButton(label: 'Save', onTap: () => Navigator.pop(ctx, SaveChoice.save)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return r ?? SaveChoice.cancel;
}

Future<bool> showConfirmDialog(BuildContext context, {required String title, String? message, String confirm = 'OK', bool danger = false}) async {
  final bool? r = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) {
      final IdeTheme t = ctx.read<Ide>().effectiveTheme;
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(ctx, false),
          const SingleActivator(LogicalKeyboardKey.enter): () => Navigator.pop(ctx, true),
        },
        child: Focus(
          autofocus: true,
          child: _dialogShell(
            ctx,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: uiText(t, size: 15, weight: FontWeight.w600)),
                if (message != null) ...[const SizedBox(height: 10), Text(message, style: uiText(t, color: t.textMuted))],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AccentButton(label: 'Cancel', subtle: true, onTap: () => Navigator.pop(ctx, false)),
                    const SizedBox(width: 8),
                    AccentButton(label: confirm, onTap: () => Navigator.pop(ctx, true)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return r ?? false;
}

Future<String?> showInputDialog(BuildContext context, {required String title, String initial = '', String? hint, String confirm = 'OK', TextSelection? selection}) {
  final TextEditingController c = TextEditingController(text: initial);
  if (selection != null) c.selection = selection;
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) {
      final IdeTheme t = ctx.read<Ide>().effectiveTheme;
      return CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(ctx)},
        child: _dialogShell(
          ctx,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: uiText(t, size: 15, weight: FontWeight.w600)),
              const SizedBox(height: 14),
              IdeTextField(controller: c, hint: hint, autofocus: true, onSubmitted: (v) => Navigator.pop(ctx, v)),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AccentButton(label: 'Cancel', subtle: true, onTap: () => Navigator.pop(ctx)),
                  const SizedBox(width: 8),
                  AccentButton(label: confirm, onTap: () => Navigator.pop(ctx, c.text)),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
