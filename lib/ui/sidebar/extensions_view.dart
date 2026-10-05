import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/ide.dart';
import '../../services/extension_service.dart';
import '../../theme/ide_theme.dart';
import '../../workspace/editor_document.dart';
import '../pages/extension_detail.dart';
import '../widgets.dart';

class ExtensionsView extends StatefulWidget {
  const ExtensionsView({super.key});

  @override
  State<ExtensionsView> createState() => _ExtensionsViewState();
}

class _ExtensionsViewState extends State<ExtensionsView> {
  String _q = '';
  bool _installedOpen = true;
  bool _marketOpen = true;

  bool _match(ExtensionInfo e) => _q.isEmpty || '${e.name} ${e.description} ${e.id}'.toLowerCase().contains(_q);

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final ExtensionService ext = context.watch<ExtensionService>();
    final List<ExtensionInfo> installed = ext.all.where((e) => ext.isInstalled(e.id) && _match(e)).toList();
    final List<ExtensionInfo> available = ext.remoteCatalog.where((e) => !ext.isInstalled(e.id) && _match(e)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PaneHeader(title: 'Extensions', actions: [
        IconBtn(icon: Icons.refresh_rounded, size: 15, tooltip: 'Refresh Marketplace', onTap: ext.fetchCatalog),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: IdeTextField(hint: 'Search Extensions', prefix: Icon(Icons.search_rounded, size: 16, color: t.textFaint), onChanged: (v) => setState(() => _q = v.toLowerCase())),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          PaneHeader(title: 'Installed', expanded: _installedOpen, onTap: () => setState(() => _installedOpen = !_installedOpen), actions: [
            Text('${installed.length}', style: uiText(t, size: 11, color: t.textFaint)),
          ]),
          if (_installedOpen) for (final ExtensionInfo e in installed) _ExtRow(info: e),
          PaneHeader(title: 'Marketplace', expanded: _marketOpen, onTap: () => setState(() => _marketOpen = !_marketOpen)),
          if (_marketOpen) ...[
            if (ext.loadingCatalog) Padding(padding: const EdgeInsets.all(16), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: t.accent)))),
            if (ext.catalogError != null)
              Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: Text(ext.catalogError!, style: uiText(t, size: 12, color: t.textMuted))),
            if (!ext.loadingCatalog && ext.catalogError == null && available.isEmpty)
              Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: Text(_q.isEmpty ? 'Everything is installed 🎉' : 'No matching extensions.', style: uiText(t, size: 12, color: t.textFaint))),
            for (final ExtensionInfo e in available) _ExtRow(info: e),
          ],
        ]),
      ),
    ]);
  }
}

class _ExtRow extends StatelessWidget {
  const _ExtRow({required this.info});

  final ExtensionInfo info;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Ide ide = context.read<Ide>();
    final ExtensionService ext = context.read<ExtensionService>();
    final bool installed = ext.isInstalled(info.id);
    final bool enabled = ext.isEnabled(info.id);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: HoverBox(
        radius: 8,
        onTap: () => ide.workspace.openSpecial(TabKind.extension, extra: info.id),
        padding: const EdgeInsets.all(8),
        child: Opacity(
          opacity: installed && !enabled ? 0.55 : 1,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ExtensionIcon(info: info, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(info.name, style: uiText(t, size: 13, weight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                  if (info.core) Icon(Icons.verified_rounded, size: 13, color: t.accent),
                ]),
                const SizedBox(height: 2),
                Text(info.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: uiText(t, size: 11.5, color: t.textMuted, height: 1.35)),
                const SizedBox(height: 5),
                Row(children: [
                  Text(info.publisher, style: uiText(t, size: 11, color: t.textFaint)),
                  const Spacer(),
                  if (!installed)
                    _Pill(label: 'Install', filled: true, onTap: () async {
                      final bool ok = await ext.install(info);
                      ok ? ide.notifications.success('${info.name} installed') : ide.notifications.error('Could not install ${info.name}');
                    })
                  else if (!info.core)
                    _Pill(label: enabled ? 'Disable' : 'Enable', filled: !enabled, onTap: () => ext.setEnabled(info.id, !enabled)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.onTap, this.filled = false});

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    return HoverBox(
      onTap: onTap,
      radius: 6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: filled ? t.accent : null,
          borderRadius: BorderRadius.circular(6),
          border: filled ? null : Border.all(color: t.border),
        ),
        child: Text(label, style: uiText(t, size: 11, color: filled ? t.onAccent : t.textMuted, weight: FontWeight.w600)),
      ),
    );
  }
}
