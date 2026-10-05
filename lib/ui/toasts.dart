import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/output_service.dart';
import '../theme/ide_theme.dart';
import 'widgets.dart';

class ToastLayer extends StatelessWidget {
  const ToastLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final NotificationService n = context.watch<NotificationService>();
    return Positioned(
      right: 16,
      bottom: 38,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final Toast t in n.toasts)
            Padding(
              key: ValueKey(t.id),
              padding: const EdgeInsets.only(top: 8),
              child: _ToastCard(toast: t, onClose: () => n.dismiss(t.id)),
            ),
        ],
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.toast, required this.onClose});

  final Toast toast;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final (IconData icon, Color color) = switch (toast.kind) {
      ToastKind.info => (Icons.info_outline_rounded, t.info),
      ToastKind.success => (Icons.check_circle_outline_rounded, t.success),
      ToastKind.warning => (Icons.warning_amber_rounded, t.warning),
      ToastKind.error => (Icons.error_outline_rounded, t.error),
    };
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 16), child: child)),
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 400,
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.borderStrong),
            boxShadow: [BoxShadow(color: t.shadow, blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (toast.progress)
                Padding(padding: const EdgeInsets.only(top: 2), child: SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: t.accent)))
              else
                Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SelectableText(toast.message, style: uiText(t, size: 13, weight: FontWeight.w500)),
                  if (toast.detail != null) ...[
                    const SizedBox(height: 3),
                    SelectableText(toast.detail!, style: uiText(t, size: 12, color: t.textMuted)),
                  ],
                ]),
              ),
              IconBtn(icon: Icons.close_rounded, size: 14, box: 22, onTap: onClose),
            ]),
            if (toast.actions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                for (int i = 0; i < toast.actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  AccentButton(
                    label: toast.actions[i].label,
                    subtle: i > 0,
                    dense: true,
                    onTap: () {
                      onClose();
                      toast.actions[i].onPressed();
                    },
                  ),
                ],
                const SizedBox(width: 6),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}
