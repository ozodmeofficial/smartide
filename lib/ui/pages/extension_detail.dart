import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/ide.dart';
import '../../core/languages.dart';
import '../../core/toolchain.dart';
import '../../services/extension_service.dart';
import '../../theme/ide_theme.dart';
import '../widgets.dart';

class ExtensionIcon extends StatelessWidget {
  const ExtensionIcon({super.key, required this.info, this.size = 40});

  final ExtensionInfo info;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bool dark = context.t.isDark;
    final Color c = dark && info.color.computeLuminance() < 0.06 ? IdeTheme.shift(info.color, 0.3) : info.color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c.withValues(alpha: 0.28), c.withValues(alpha: 0.14)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(size * 0.26),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Icon(info.icon, size: size * 0.52, color: c),
    );
  }
}

class ExtensionDetailPage extends StatelessWidget {
  const ExtensionDetailPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Ide ide = context.watch<Ide>();
    final ExtensionService ext = context.watch<ExtensionService>();
    final Toolchain tc = context.watch<Toolchain>();
    final ExtensionInfo? info = ext.all.where((e) => e.id == id).firstOrNull;
    if (info == null) return Center(child: Text('Extension not found', style: uiText(t)));
    final bool installed = ext.isInstalled(id);
    final bool enabled = ext.isEnabled(id);
    final List<LanguageDef> langs = languages.where((l) => info.languageIds.contains(l.id)).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(36),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ExtensionIcon(info: info, size: 96),
              const SizedBox(width: 24),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(info.name, style: serifText(t, size: 30)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Text(info.publisher, style: uiText(t, color: t.accent, weight: FontWeight.w600)),
                    Text('  ·  v${info.version}  ·  ${info.id}', style: uiText(t, color: t.textFaint)),
                  ]),
                  const SizedBox(height: 10),
                  Text(info.description, style: uiText(t, size: 14.5, color: t.textMuted, height: 1.5)),
                  const SizedBox(height: 16),
                  Row(children: [
                    if (info.core)
                      const AccentButton(label: 'Built in', subtle: true, icon: Icons.verified_rounded)
                    else if (!installed)
                      AccentButton(label: 'Install', icon: Icons.download_rounded, onTap: () async {
                        final bool ok = await ext.install(info);
                        ok ? ide.notifications.success('${info.name} installed') : ide.notifications.error('Installation failed');
                      })
                    else ...[
                      AccentButton(label: enabled ? 'Disable' : 'Enable', subtle: enabled, icon: enabled ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded, onTap: () => ext.setEnabled(id, !enabled)),
                      if (info.remote) ...[
                        const SizedBox(width: 8),
                        AccentButton(label: 'Uninstall', subtle: true, icon: Icons.delete_outline_rounded, onTap: () => ext.uninstall(id)),
                      ],
                    ],
                  ]),
                ]),
              ),
            ]),
            const SizedBox(height: 28),
            Container(height: 1, color: t.border),
            const SizedBox(height: 22),
            if (info.features.isNotEmpty) ...[
              Text('Features', style: serifText(t, size: 20)),
              const SizedBox(height: 10),
              for (final String f in info.features)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.check_rounded, size: 17, color: t.success),
                    const SizedBox(width: 10),
                    Expanded(child: Text(f, style: uiText(t, size: 13.5))),
                  ]),
                ),
              const SizedBox(height: 22),
            ],
            if (langs.isNotEmpty) ...[
              Text('Languages', style: serifText(t, size: 20)),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final LanguageDef l in langs)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: t.border)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      LanguageBadge(badge: l.badge, color: l.color, size: 22),
                      const SizedBox(width: 8),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.name, style: uiText(t, size: 13, weight: FontWeight.w600)),
                        Text('${l.extensions.take(4).join(' ')}${l.snippets.isNotEmpty ? ' · ${l.snippets.length} snippets' : ''}', style: uiText(t, size: 11, color: t.textFaint)),
                      ]),
                    ]),
                  ),
              ]),
              const SizedBox(height: 22),
            ],
            if (info.requirements.isNotEmpty || langs.any((l) => l.lsp != null)) ...[
              Text('Requirements on this computer', style: serifText(t, size: 20)),
              const SizedBox(height: 10),
              for (final String req in info.requirements)
                if (tc[req] != null) _ReqRow(tool: tc[req]!),
              for (final LanguageDef l in langs)
                if (l.lsp != null)
                  _LspRow(name: '${l.name} language server', command: l.lsp!.command, hint: l.lsp!.installHint),
            ],
          ]),
        ),
      ),
    );
  }
}

class _ReqRow extends StatelessWidget {
  const _ReqRow({required this.tool});

  final ToolInfo tool;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Ide ide = context.read<Ide>();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: t.border)),
      child: Row(children: [
        Icon(tool.available ? Icons.check_circle_rounded : Icons.error_outline_rounded, size: 18, color: tool.available ? t.success : t.warning),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tool.name, style: uiText(t, size: 13.5, weight: FontWeight.w600)),
            Text(tool.available ? 'Found: ${tool.resolved} ${tool.version ?? ''}' : 'Not installed — ${tool.installHint}', style: uiText(t, size: 12, color: t.textMuted)),
          ]),
        ),
        if (!tool.available)
          AccentButton(label: 'Install', dense: true, onTap: () {
            ide.showPanel(PanelTab.terminal);
            ide.terminals.sendToActive(tool.installHint.split('  ').first);
          }),
      ]),
    );
  }
}

class _LspRow extends StatelessWidget {
  const _LspRow({required this.name, required this.command, required this.hint});

  final String name, command, hint;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    return FutureBuilder<String?>(
      future: Toolchain.which(command),
      builder: (context, s) {
        final bool ok = s.data != null;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: t.border)),
          child: Row(children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.lightbulb_outline_rounded, size: 18, color: ok ? t.success : t.info),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$name (optional)', style: uiText(t, size: 13.5, weight: FontWeight.w600)),
                Text(ok ? 'Found: ${s.data}' : 'For IntelliSense install: $hint', style: uiText(t, size: 12, color: t.textMuted)),
              ]),
            ),
          ]),
        );
      },
    );
  }
}
