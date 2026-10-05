import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart' show TerminalTheme;

/// Compact description of a colour scheme. Every SmartIDE theme is defined by
/// one of these; the full set of UI and syntax colours is derived from it so
/// that adding a new theme takes a dozen lines instead of hundreds.
class ThemePalette {
  const ThemePalette({
    required this.bg,
    required this.fg,
    required this.accent,
    required this.comment,
    required this.keyword,
    required this.string,
    required this.number,
    required this.function,
    required this.type,
    required this.variable,
    Color? constant,
    Color? tag,
    Color? attr,
    Color? operator,
    this.chrome,
    this.surface,
    this.border,
    this.selection,
    this.onAccent,
    this.red,
    this.green,
    this.yellow,
    this.blue,
    this.magenta,
    this.cyan,
  })  : constant = constant ?? number,
        tag = tag ?? keyword,
        attr = attr ?? type,
        operator = operator ?? fg;

  final Color bg;
  final Color fg;
  final Color accent;
  final Color comment;
  final Color keyword;
  final Color string;
  final Color number;
  final Color function;
  final Color type;
  final Color variable;
  final Color constant;
  final Color tag;
  final Color attr;
  final Color operator;

  /// Optional explicit overrides for the derived UI colours.
  final Color? chrome;
  final Color? surface;
  final Color? border;
  final Color? selection;
  final Color? onAccent;

  /// Optional terminal ANSI overrides.
  final Color? red;
  final Color? green;
  final Color? yellow;
  final Color? blue;
  final Color? magenta;
  final Color? cyan;
}

/// All colours used by the workbench.
class IdeTheme {
  IdeTheme._({
    required this.id,
    required this.name,
    required this.isDark,
    required this.palette,
    required this.editorBg,
    required this.chrome,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.hover,
    required this.selection,
    required this.lineHighlight,
    required this.inputBg,
    required this.shadow,
    required this.error,
    required this.warning,
    required this.info,
    required this.success,
    required this.gitAdded,
    required this.gitModified,
    required this.gitDeleted,
    required this.gitUntracked,
    required this.syntax,
    required this.terminal,
  });

  final String id;
  final String name;
  final bool isDark;
  final ThemePalette palette;

  /// Background of the editor / main content cards.
  final Color editorBg;

  /// Window background: title bar, activity bar, side bar.
  final Color chrome;

  /// Raised surfaces: popups, menus, palettes.
  final Color surface;
  final Color surfaceHigh;
  final Color border;
  final Color borderStrong;
  final Color text;
  final Color textMuted;
  final Color textFaint;
  final Color accent;
  final Color onAccent;
  final Color accentSoft;
  final Color hover;
  final Color selection;
  final Color lineHighlight;
  final Color inputBg;
  final Color shadow;
  final Color error;
  final Color warning;
  final Color info;
  final Color success;
  final Color gitAdded;
  final Color gitModified;
  final Color gitDeleted;
  final Color gitUntracked;
  final Map<String, TextStyle> syntax;
  final TerminalTheme terminal;

  factory IdeTheme.fromPalette({
    required String id,
    required String name,
    required bool dark,
    required ThemePalette p,
  }) {
    final Color chrome = p.chrome ?? _shift(p.bg, dark ? -0.025 : -0.03);
    final Color surface = p.surface ?? _shift(p.bg, dark ? 0.045 : 0.0);
    final Color border = p.border ?? p.fg.withValues(alpha: dark ? 0.10 : 0.12);
    final Color onAccent = p.onAccent ?? (_luma(p.accent) > 0.55 ? const Color(0xFF1A1A1A) : Colors.white);
    final Color red = p.red ?? (dark ? const Color(0xFFF26D6D) : const Color(0xFFD1242F));
    final Color green = p.green ?? (dark ? const Color(0xFF7CC47F) : const Color(0xFF1A7F37));
    final Color yellow = p.yellow ?? (dark ? const Color(0xFFE5C07B) : const Color(0xFF9A6700));
    final Color blue = p.blue ?? (dark ? const Color(0xFF6CA8F0) : const Color(0xFF0969DA));
    final Color magenta = p.magenta ?? p.keyword;
    final Color cyan = p.cyan ?? (dark ? const Color(0xFF56C2C9) : const Color(0xFF1B7C83));
    return IdeTheme._(
      id: id,
      name: name,
      isDark: dark,
      palette: p,
      editorBg: p.bg,
      chrome: chrome,
      surface: surface,
      surfaceHigh: _shift(surface, dark ? 0.04 : -0.03),
      border: border,
      borderStrong: p.fg.withValues(alpha: dark ? 0.18 : 0.22),
      text: p.fg,
      textMuted: p.fg.withValues(alpha: 0.68),
      textFaint: p.fg.withValues(alpha: 0.42),
      accent: p.accent,
      onAccent: onAccent,
      accentSoft: p.accent.withValues(alpha: dark ? 0.16 : 0.12),
      hover: p.fg.withValues(alpha: dark ? 0.06 : 0.055),
      selection: p.selection ?? p.accent.withValues(alpha: dark ? 0.28 : 0.22),
      lineHighlight: p.fg.withValues(alpha: dark ? 0.04 : 0.045),
      inputBg: dark ? _shift(p.bg, -0.035) : _shift(p.bg, 0.0),
      shadow: Colors.black.withValues(alpha: dark ? 0.45 : 0.14),
      error: red,
      warning: yellow,
      info: blue,
      success: green,
      gitAdded: green,
      gitModified: yellow,
      gitDeleted: red,
      gitUntracked: green.withValues(alpha: 0.85),
      syntax: _buildSyntax(p),
      terminal: TerminalTheme(
        cursor: p.accent,
        selection: p.accent.withValues(alpha: 0.35),
        foreground: p.fg,
        background: p.bg,
        black: dark ? _shift(p.bg, 0.08) : const Color(0xFF24292F),
        red: red,
        green: green,
        yellow: yellow,
        blue: blue,
        magenta: magenta,
        cyan: cyan,
        white: dark ? p.fg.withValues(alpha: 0.85) : const Color(0xFF6E7781),
        brightBlack: p.comment,
        brightRed: _shift(red, dark ? 0.08 : -0.05),
        brightGreen: _shift(green, dark ? 0.08 : -0.05),
        brightYellow: _shift(yellow, dark ? 0.08 : -0.05),
        brightBlue: _shift(blue, dark ? 0.08 : -0.05),
        brightMagenta: _shift(magenta, dark ? 0.08 : -0.05),
        brightCyan: _shift(cyan, dark ? 0.08 : -0.05),
        brightWhite: dark ? p.fg : const Color(0xFF57606A),
        searchHitBackground: p.accent.withValues(alpha: 0.35),
        searchHitBackgroundCurrent: p.accent.withValues(alpha: 0.65),
        searchHitForeground: p.fg,
      ),
    );
  }

  /// Material theme used by stock widgets (text fields, scrollbars, ...).
  ThemeData toMaterial({String? uiFont}) {
    final ColorScheme scheme = ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: accent,
      onPrimary: onAccent,
      secondary: accent,
      onSecondary: onAccent,
      error: error,
      onError: Colors.white,
      surface: surface,
      onSurface: text,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: uiFont,
      scaffoldBackgroundColor: chrome,
      canvasColor: surface,
      dividerColor: border,
      hoverColor: hover,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      focusColor: accentSoft,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: selection,
        selectionHandleColor: accent,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(8),
        radius: const Radius.circular(8),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => text.withValues(alpha: states.contains(WidgetState.hovered) ? 0.28 : 0.16),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        textStyle: TextStyle(color: text, fontSize: 12),
        decoration: BoxDecoration(
          color: surfaceHigh,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
          boxShadow: [BoxShadow(color: shadow, blurRadius: 12, offset: const Offset(0, 4))],
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: inputBg,
        hintStyle: TextStyle(color: textFaint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: accent, width: 1.2)),
      ),
      checkboxTheme: CheckboxThemeData(
        side: BorderSide(color: textMuted),
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : Colors.transparent),
        checkColor: WidgetStateProperty.all(onAccent),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? onAccent : textMuted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : hover),
        trackOutlineColor: WidgetStateProperty.all(border),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        thumbColor: accent,
        inactiveTrackColor: border,
        overlayShape: SliderComponentShape.noOverlay,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent, linearTrackColor: accentSoft),
    );
  }

  static Map<String, TextStyle> _buildSyntax(ThemePalette p) {
    TextStyle c(Color color, {bool italic = false, bool bold = false}) => TextStyle(
          color: color,
          fontStyle: italic ? FontStyle.italic : null,
          fontWeight: bold ? FontWeight.w600 : null,
        );
    final TextStyle base = TextStyle(color: p.fg);
    final TextStyle comment = c(p.comment, italic: true);
    final TextStyle keyword = c(p.keyword);
    final TextStyle string = c(p.string);
    final TextStyle number = c(p.number);
    final TextStyle fn = c(p.function);
    final TextStyle type = c(p.type);
    final TextStyle variable = c(p.variable);
    final TextStyle constant = c(p.constant);
    final TextStyle tag = c(p.tag);
    final TextStyle attr = c(p.attr);
    return {
      'root': base,
      'comment': comment,
      'quote': comment,
      'doctag': keyword,
      'keyword': keyword,
      'meta-keyword': keyword,
      'meta keyword': keyword,
      'selector-tag': tag,
      'built_in': type,
      'type': type,
      'class': type,
      'title.class_': type,
      'title.class.inherited__': type,
      'class-title': type,
      'literal': constant,
      'number': number,
      'symbol': constant,
      'bullet': keyword,
      'operator': c(p.operator),
      'punctuation': base,
      'property': variable,
      'regexp': string,
      'string': string,
      'meta-string': string,
      'meta string': string,
      'char.escape_': constant,
      'subst': base,
      'template-variable': variable,
      'template-tag': keyword,
      'variable': variable,
      'variable.language_': keyword,
      'variable.constant_': constant,
      'title': fn,
      'title.function_': fn,
      'title.function.invoke__': fn,
      'function': fn,
      'params': base,
      'meta': c(p.comment.withValues(alpha: 1)),
      'meta.prompt_': comment,
      'section': c(p.function, bold: true),
      'tag': base,
      'name': tag,
      'attr': attr,
      'attribute': attr,
      'selector-id': fn,
      'selector-class': attr,
      'selector-attr': attr,
      'selector-pseudo': keyword,
      'link': c(p.function).copyWith(decoration: TextDecoration.underline),
      'addition': c(p.green ?? p.string),
      'deletion': c(p.red ?? p.keyword),
      'code': string,
      'formula': keyword,
      'emphasis': const TextStyle(fontStyle: FontStyle.italic),
      'strong': const TextStyle(fontWeight: FontWeight.bold),
    };
  }

  static double _luma(Color c) => c.computeLuminance();

  /// Lightens (amount > 0) or darkens (amount < 0) a colour.
  static Color _shift(Color c, double amount) {
    final HSLColor hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
  }

  static Color shift(Color c, double amount) => _shift(c, amount);
}
