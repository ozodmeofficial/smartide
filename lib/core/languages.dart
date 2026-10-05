import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cmake.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/diff.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/dos.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/less.dart';
import 'package:re_highlight/languages/lua.dart';
import 'package:re_highlight/languages/makefile.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/plaintext.dart';
import 'package:re_highlight/languages/powershell.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/scss.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart' show Mode;

/// Information handed to a language's run command builder.
class RunContext {
  RunContext({required this.file, required this.workspace, required this.tools});

  final String file;
  final String? workspace;

  /// Resolved executable names from [Toolchain] (e.g. `python` -> `py`).
  final Map<String, String> tools;

  bool get isWindows => Platform.isWindows;
  String get dir => p.dirname(file);
  String get name => p.basename(file);
  String get stem => p.basenameWithoutExtension(file);
  String get exe => isWindows ? '${p.join(dir, stem)}.exe' : p.join(dir, stem);
  String tool(String id) => tools[id] ?? id;

  static String q(String s) => s.contains(' ') || s.contains('&') || s.contains('(') ? '"$s"' : s;

  String findUp(String marker) {
    String d = dir;
    while (true) {
      if (File(p.join(d, marker)).existsSync() || Directory(p.join(d, marker)).existsSync()) return d;
      final String parent = p.dirname(d);
      if (parent == d || (workspace != null && !p.isWithin(workspace!, d) && d != workspace)) return '';
      d = parent;
    }
  }

  String? findUpGlob(String extension) {
    String d = dir;
    for (int i = 0; i < 6; i++) {
      try {
        final List<FileSystemEntity> hits =
            Directory(d).listSync().where((e) => e is File && e.path.endsWith(extension)).toList();
        if (hits.isNotEmpty) return hits.first.path;
      } catch (_) {}
      final String parent = p.dirname(d);
      if (parent == d) break;
      d = parent;
    }
    return null;
  }
}

/// A Language Server configuration. The server must be installed on the
/// user's machine; SmartIDE only spawns it.
class LspSpec {
  const LspSpec(this.command, this.args, this.installHint);

  final String command;
  final List<String> args;
  final String installHint;
}

class Snippet {
  const Snippet(this.prefix, this.label, this.body);

  final String prefix;
  final String label;

  /// Body with `${1:placeholder}`, `$1` and `$0` tab stops.
  final String body;
}

class LanguageDef {
  const LanguageDef({
    required this.id,
    required this.name,
    required this.extensions,
    required this.mode,
    required this.badge,
    required this.color,
    this.fileNames = const [],
    this.lineComment,
    this.blockComment,
    this.run,
    this.lsp,
    this.snippets = const [],
    this.extensionId,
  });

  final String id;
  final String name;
  final List<String> extensions;
  final List<String> fileNames;
  final Mode mode;

  /// Short label used for file icons, e.g. "py".
  final String badge;
  final Color color;
  final String? lineComment;
  final (String, String)? blockComment;
  final String? Function(RunContext c)? run;
  final LspSpec? lsp;
  final List<Snippet> snippets;

  /// The built-in extension that provides this language (can be disabled).
  final String? extensionId;
}

String? _cOrCpp(RunContext c, String compiler) {
  final String out = RunContext.q(c.exe);
  final String src = RunContext.q(c.file);
  final String std = compiler == 'g++' ? ' -std=c++20' : '';
  return '${c.tool(compiler)}$std -g $src -o $out && $out';
}

final List<LanguageDef> languages = [
  LanguageDef(
    id: 'python',
    name: 'Python',
    extensions: ['.py', '.pyw', '.pyi'],
    mode: langPython,
    badge: 'py',
    color: const Color(0xFF3B82C4),
    lineComment: '#',
    blockComment: ('"""', '"""'),
    extensionId: 'smartide.python',
    run: (c) => '${c.tool('python')} -u ${RunContext.q(c.file)}',
    lsp: const LspSpec('pyright-langserver', ['--stdio'], 'pip install pyright  (or)  npm i -g pyright'),
    snippets: const [
      Snippet('def', 'function', 'def \${1:name}(\${2:args}):\n    \${0:pass}'),
      Snippet('class', 'class', 'class \${1:Name}:\n    def __init__(self\${2:, args}):\n        \${0:pass}'),
      Snippet('ifmain', 'if __name__ == "__main__"', 'if __name__ == "__main__":\n    \${0:main()}'),
      Snippet('for', 'for loop', 'for \${1:item} in \${2:items}:\n    \${0:pass}'),
      Snippet('fori', 'for range', 'for \${1:i} in range(\${2:10}):\n    \${0:pass}'),
      Snippet('while', 'while loop', 'while \${1:condition}:\n    \${0:pass}'),
      Snippet('try', 'try/except', 'try:\n    \${1:pass}\nexcept \${2:Exception} as \${3:e}:\n    \${0:print(e)}'),
      Snippet('with', 'with open', 'with open(\${1:"file.txt"}, \${2:"r"}, encoding="utf-8") as \${3:f}:\n    \${0:data = f.read()}'),
      Snippet('pr', 'print', 'print(\${0})'),
      Snippet('lc', 'list comprehension', '[\${1:x} for \${1:x} in \${2:items}\${3: if cond}]'),
    ],
  ),
  LanguageDef(
    id: 'c',
    name: 'C',
    extensions: ['.c', '.h'],
    mode: langC,
    badge: 'C',
    color: const Color(0xFF5C8DBC),
    lineComment: '//',
    blockComment: ('/*', '*/'),
    extensionId: 'smartide.cpp',
    run: (c) => _cOrCpp(c, 'gcc'),
    lsp: const LspSpec('clangd', [], 'Install LLVM (winget install LLVM.LLVM) to get clangd'),
    snippets: const [
      Snippet('main', 'main()', '#include <stdio.h>\n\nint main(void) {\n    \${0:printf("Hello, World!\\n");}\n    return 0;\n}'),
      Snippet('inc', '#include', '#include <\${1:stdio.h}>'),
      Snippet('for', 'for loop', 'for (int \${1:i} = 0; \${1:i} < \${2:n}; \${1:i}++) {\n    \${0}\n}'),
      Snippet('if', 'if', 'if (\${1:condition}) {\n    \${0}\n}'),
      Snippet('while', 'while', 'while (\${1:condition}) {\n    \${0}\n}'),
      Snippet('struct', 'struct', 'typedef struct {\n    \${0}\n} \${1:Name};'),
      Snippet('pf', 'printf', 'printf("\${1:%d}\\n", \${0});'),
    ],
  ),
  LanguageDef(
    id: 'cpp',
    name: 'C++',
    extensions: ['.cpp', '.cc', '.cxx', '.hpp', '.hh', '.hxx', '.ino'],
    mode: langCpp,
    badge: 'C++',
    color: const Color(0xFF00599C),
    lineComment: '//',
    blockComment: ('/*', '*/'),
    extensionId: 'smartide.cpp',
    run: (c) => _cOrCpp(c, 'g++'),
    lsp: const LspSpec('clangd', [], 'Install LLVM (winget install LLVM.LLVM) to get clangd'),
    snippets: const [
      Snippet('main', 'main()', '#include <iostream>\n\nint main() {\n    \${0:std::cout << "Hello, World!" << std::endl;}\n    return 0;\n}'),
      Snippet('inc', '#include', '#include <\${1:iostream}>'),
      Snippet('for', 'for loop', 'for (int \${1:i} = 0; \${1:i} < \${2:n}; ++\${1:i}) {\n    \${0}\n}'),
      Snippet('fore', 'range-for', 'for (auto& \${1:item} : \${2:items}) {\n    \${0}\n}'),
      Snippet('class', 'class', 'class \${1:Name} {\npublic:\n    \${1:Name}();\n    ~\${1:Name}();\n\nprivate:\n    \${0}\n};'),
      Snippet('cout', 'std::cout', 'std::cout << \${0} << std::endl;'),
      Snippet('cin', 'std::cin', 'std::cin >> \${0};'),
      Snippet('vec', 'std::vector', 'std::vector<\${1:int}> \${0:v};'),
    ],
  ),
  LanguageDef(
    id: 'csharp',
    name: 'C#',
    extensions: ['.cs', '.csx'],
    mode: langCsharp,
    badge: 'C#',
    color: const Color(0xFF9B4F96),
    lineComment: '//',
    blockComment: ('/*', '*/'),
    extensionId: 'smartide.csharp',
    run: (c) {
      final String? proj = c.findUpGlob('.csproj');
      if (proj != null) return '${c.tool('dotnet')} run --project ${RunContext.q(proj)}';
      // .NET 10+ can run a single .cs file directly.
      return '${c.tool('dotnet')} run ${RunContext.q(c.file)}';
    },
    lsp: const LspSpec('csharp-ls', [], 'dotnet tool install --global csharp-ls'),
    snippets: const [
      Snippet('main', 'Main', 'static void Main(string[] args)\n{\n    \${0}\n}'),
      Snippet('cw', 'Console.WriteLine', 'Console.WriteLine(\${0});'),
      Snippet('class', 'class', 'public class \${1:Name}\n{\n    \${0}\n}'),
      Snippet('prop', 'property', 'public \${1:int} \${2:Name} { get; set; }'),
      Snippet('for', 'for', 'for (int \${1:i} = 0; \${1:i} < \${2:length}; \${1:i}++)\n{\n    \${0}\n}'),
      Snippet('foreach', 'foreach', 'foreach (var \${1:item} in \${2:collection})\n{\n    \${0}\n}'),
      Snippet('try', 'try/catch', 'try\n{\n    \${1}\n}\ncatch (\${2:Exception} ex)\n{\n    \${0}\n}'),
    ],
  ),
  LanguageDef(
    id: 'go',
    name: 'Go',
    extensions: ['.go'],
    fileNames: ['go.mod'],
    mode: langGo,
    badge: 'go',
    color: const Color(0xFF00ADD8),
    lineComment: '//',
    blockComment: ('/*', '*/'),
    extensionId: 'smartide.go',
    run: (c) {
      final String mod = c.findUp('go.mod');
      if (mod.isNotEmpty && c.file.endsWith('.go')) return '${c.tool('go')} run .';
      return '${c.tool('go')} run ${RunContext.q(c.file)}';
    },
    lsp: const LspSpec('gopls', [], 'go install golang.org/x/tools/gopls@latest'),
    snippets: const [
      Snippet('main', 'package main', 'package main\n\nimport "fmt"\n\nfunc main() {\n\t\${0:fmt.Println("Hello, World!")}\n}'),
      Snippet('func', 'func', 'func \${1:name}(\${2}) \${3:error} {\n\t\${0}\n}'),
      Snippet('iferr', 'if err != nil', 'if err != nil {\n\t\${0:return err}\n}'),
      Snippet('for', 'for', 'for \${1:i} := 0; \${1:i} < \${2:n}; \${1:i}++ {\n\t\${0}\n}'),
      Snippet('forr', 'for range', 'for \${1:_}, \${2:v} := range \${3:items} {\n\t\${0}\n}'),
      Snippet('st', 'struct', 'type \${1:Name} struct {\n\t\${0}\n}'),
      Snippet('pl', 'fmt.Println', 'fmt.Println(\${0})'),
    ],
  ),
  LanguageDef(
    id: 'javascript',
    name: 'JavaScript',
    extensions: ['.js', '.mjs', '.cjs', '.jsx'],
    mode: langJavascript,
    badge: 'JS',
    color: const Color(0xFFE8C547),
    lineComment: '//',
    blockComment: ('/*', '*/'),
    extensionId: 'smartide.web',
    run: (c) => '${c.tool('node')} ${RunContext.q(c.file)}',
    lsp: const LspSpec('typescript-language-server', ['--stdio'], 'npm i -g typescript typescript-language-server'),
    snippets: const [
      Snippet('log', 'console.log', 'console.log(\${0});'),
      Snippet('fn', 'function', 'function \${1:name}(\${2}) {\n  \${0}\n}'),
      Snippet('af', 'arrow function', 'const \${1:name} = (\${2}) => {\n  \${0}\n};'),
      Snippet('for', 'for loop', 'for (let \${1:i} = 0; \${1:i} < \${2:arr}.length; \${1:i}++) {\n  \${0}\n}'),
      Snippet('forof', 'for...of', 'for (const \${1:item} of \${2:items}) {\n  \${0}\n}'),
      Snippet('imp', 'import', "import \${1:name} from '\${0:module}';"),
      Snippet('afn', 'async function', 'async function \${1:name}(\${2}) {\n  \${0}\n}'),
      Snippet('try', 'try/catch', 'try {\n  \${1}\n} catch (\${2:err}) {\n  \${0:console.error(err);}\n}'),
    ],
  ),
  LanguageDef(
    id: 'typescript',
    name: 'TypeScript',
    extensions: ['.ts', '.tsx', '.mts', '.cts'],
    mode: langTypescript,
    badge: 'TS',
    color: const Color(0xFF3178C6),
    lineComment: '//',
    blockComment: ('/*', '*/'),
    extensionId: 'smartide.web',
    run: (c) => 'npx --yes tsx ${RunContext.q(c.file)}',
    lsp: const LspSpec('typescript-language-server', ['--stdio'], 'npm i -g typescript typescript-language-server'),
    snippets: const [
      Snippet('log', 'console.log', 'console.log(\${0});'),
      Snippet('int', 'interface', 'interface \${1:Name} {\n  \${0}\n}'),
      Snippet('type', 'type alias', 'type \${1:Name} = \${0};'),
      Snippet('af', 'arrow function', 'const \${1:name} = (\${2}): \${3:void} => {\n  \${0}\n};'),
      Snippet('class', 'class', 'class \${1:Name} {\n  constructor(\${2}) {\n    \${0}\n  }\n}'),
    ],
  ),
  LanguageDef(
    id: 'html',
    name: 'HTML',
    extensions: ['.html', '.htm', '.xhtml'],
    mode: langXml,
    badge: '<>',
    color: const Color(0xFFE44D26),
    blockComment: ('<!--', '-->'),
    extensionId: 'smartide.web',
    lsp: const LspSpec('vscode-html-language-server', ['--stdio'], 'npm i -g vscode-langservers-extracted'),
    snippets: const [
      Snippet('!', 'HTML5 boilerplate', '<!DOCTYPE html>\n<html lang="en">\n<head>\n  <meta charset="UTF-8">\n  <meta name="viewport" content="width=device-width, initial-scale=1.0">\n  <title>\${1:Document}</title>\n  <link rel="stylesheet" href="\${2:style.css}">\n</head>\n<body>\n  \${0}\n  <script src="\${3:script.js}"></script>\n</body>\n</html>'),
      Snippet('div', '<div>', '<div class="\${1}">\${0}</div>'),
      Snippet('a', '<a>', '<a href="\${1:#}">\${0}</a>'),
      Snippet('img', '<img>', '<img src="\${1}" alt="\${0}">'),
      Snippet('ul', '<ul>', '<ul>\n  <li>\${0}</li>\n</ul>'),
      Snippet('script', '<script>', '<script src="\${0}"></script>'),
      Snippet('link', '<link css>', '<link rel="stylesheet" href="\${0:style.css}">'),
      Snippet('btn', '<button>', '<button type="\${1:button}">\${0}</button>'),
      Snippet('input', '<input>', '<input type="\${1:text}" name="\${2}" placeholder="\${0}">'),
    ],
  ),
  LanguageDef(
    id: 'css',
    name: 'CSS',
    extensions: ['.css'],
    mode: langCss,
    badge: '#',
    color: const Color(0xFF2965F1),
    blockComment: ('/*', '*/'),
    extensionId: 'smartide.web',
    lsp: const LspSpec('vscode-css-language-server', ['--stdio'], 'npm i -g vscode-langservers-extracted'),
    snippets: const [
      Snippet('flex', 'flex center', 'display: flex;\njustify-content: \${1:center};\nalign-items: \${0:center};'),
      Snippet('grid', 'grid', 'display: grid;\ngrid-template-columns: \${1:repeat(3, 1fr)};\ngap: \${0:16px};'),
      Snippet('media', '@media', '@media (max-width: \${1:768px}) {\n  \${0}\n}'),
    ],
  ),
  LanguageDef(id: 'scss', name: 'SCSS', extensions: ['.scss', '.sass'], mode: langScss, badge: 'S', color: const Color(0xFFCD6799), lineComment: '//', blockComment: ('/*', '*/'), extensionId: 'smartide.web'),
  LanguageDef(id: 'less', name: 'Less', extensions: ['.less'], mode: langLess, badge: 'L', color: const Color(0xFF1D365D), lineComment: '//', blockComment: ('/*', '*/'), extensionId: 'smartide.web'),
  LanguageDef(
    id: 'json',
    name: 'JSON',
    extensions: ['.json', '.jsonc', '.code-workspace'],
    fileNames: ['.prettierrc', '.eslintrc'],
    mode: langJson,
    badge: '{}',
    color: const Color(0xFFCBA136),
    lineComment: '//',
  ),
  LanguageDef(
    id: 'java',
    name: 'Java',
    extensions: ['.java'],
    mode: langJava,
    badge: 'J',
    color: const Color(0xFFE76F00),
    lineComment: '//',
    blockComment: ('/*', '*/'),
    extensionId: 'smartide.java',
    // Java 11+ runs single source files directly.
    run: (c) => '${c.tool('java')} ${RunContext.q(c.file)}',
    lsp: const LspSpec('jdtls', [], 'Install Eclipse JDT Language Server (jdtls) and add it to PATH'),
    snippets: const [
      Snippet('main', 'public static void main', 'public static void main(String[] args) {\n    \${0}\n}'),
      Snippet('sout', 'System.out.println', 'System.out.println(\${0});'),
      Snippet('class', 'class', 'public class \${1:Main} {\n    \${0}\n}'),
      Snippet('fori', 'for', 'for (int \${1:i} = 0; \${1:i} < \${2:n}; \${1:i}++) {\n    \${0}\n}'),
    ],
  ),
  LanguageDef(
    id: 'rust',
    name: 'Rust',
    extensions: ['.rs'],
    mode: langRust,
    badge: 'rs',
    color: const Color(0xFFDEA584),
    lineComment: '//',
    blockComment: ('/*', '*/'),
    extensionId: 'smartide.rust',
    run: (c) {
      final String cargo = c.findUp('Cargo.toml');
      if (cargo.isNotEmpty) return '${c.tool('cargo')} run --manifest-path ${RunContext.q(p.join(cargo, 'Cargo.toml'))}';
      final String out = RunContext.q(c.exe);
      return '${c.tool('rustc')} ${RunContext.q(c.file)} -o $out && $out';
    },
    lsp: const LspSpec('rust-analyzer', [], 'rustup component add rust-analyzer'),
    snippets: const [
      Snippet('main', 'fn main', 'fn main() {\n    \${0:println!("Hello, world!");}\n}'),
      Snippet('fn', 'fn', 'fn \${1:name}(\${2}) -> \${3:()} {\n    \${0}\n}'),
      Snippet('pl', 'println!', 'println!("\${1:{}}", \${0});'),
      Snippet('st', 'struct', 'struct \${1:Name} {\n    \${0}\n}'),
      Snippet('impl', 'impl', 'impl \${1:Name} {\n    \${0}\n}'),
      Snippet('match', 'match', 'match \${1:value} {\n    \${2:_} => \${0},\n}'),
    ],
  ),
  LanguageDef(
    id: 'dart',
    name: 'Dart',
    extensions: ['.dart'],
    mode: langDart,
    badge: 'dt',
    color: const Color(0xFF0175C2),
    lineComment: '//',
    blockComment: ('/*', '*/'),
    extensionId: 'smartide.dart',
    run: (c) => '${c.tool('dart')} run ${RunContext.q(c.file)}',
    lsp: const LspSpec('dart', ['language-server', '--protocol=lsp'], 'Install the Dart or Flutter SDK'),
    snippets: const [
      Snippet('main', 'main()', 'void main() {\n  \${0:print(\'Hello, World!\');}\n}'),
      Snippet('stl', 'StatelessWidget', 'class \${1:MyWidget} extends StatelessWidget {\n  const \${1:MyWidget}({super.key});\n\n  @override\n  Widget build(BuildContext context) {\n    return \${0:const Placeholder()};\n  }\n}'),
      Snippet('pr', 'print', 'print(\${0});'),
    ],
  ),
  LanguageDef(
    id: 'php',
    name: 'PHP',
    extensions: ['.php'],
    mode: langPhp,
    badge: 'php',
    color: const Color(0xFF777BB4),
    lineComment: '//',
    blockComment: ('/*', '*/'),
    extensionId: 'smartide.php',
    run: (c) => '${c.tool('php')} ${RunContext.q(c.file)}',
    lsp: const LspSpec('intelephense', ['--stdio'], 'npm i -g intelephense'),
    snippets: const [
      Snippet('php', '<?php', '<?php\n\n\${0}'),
      Snippet('echo', 'echo', 'echo \${0};'),
      Snippet('fn', 'function', 'function \${1:name}(\${2}) {\n    \${0}\n}'),
    ],
  ),
  LanguageDef(id: 'ruby', name: 'Ruby', extensions: ['.rb'], fileNames: ['Gemfile', 'Rakefile'], mode: langRuby, badge: 'rb', color: const Color(0xFFCC342D), lineComment: '#', extensionId: 'smartide.ruby', run: (c) => '${c.tool('ruby')} ${RunContext.q(c.file)}', lsp: const LspSpec('solargraph', ['stdio'], 'gem install solargraph')),
  LanguageDef(id: 'kotlin', name: 'Kotlin', extensions: ['.kt', '.kts'], mode: langKotlin, badge: 'kt', color: const Color(0xFF7F52FF), lineComment: '//', blockComment: ('/*', '*/'), extensionId: 'smartide.java', run: (c) => 'kotlinc ${RunContext.q(c.file)} -include-runtime -d ${RunContext.q(p.join(c.dir, '${c.stem}.jar'))} && java -jar ${RunContext.q(p.join(c.dir, '${c.stem}.jar'))}'),
  LanguageDef(id: 'swift', name: 'Swift', extensions: ['.swift'], mode: langSwift, badge: 'sw', color: const Color(0xFFF05138), lineComment: '//', blockComment: ('/*', '*/'), run: (c) => 'swift ${RunContext.q(c.file)}'),
  LanguageDef(id: 'lua', name: 'Lua', extensions: ['.lua'], mode: langLua, badge: 'lua', color: const Color(0xFF000080), lineComment: '--', blockComment: ('--[[', ']]'), run: (c) => 'lua ${RunContext.q(c.file)}'),
  LanguageDef(
    id: 'powershell',
    name: 'PowerShell',
    extensions: ['.ps1', '.psm1', '.psd1'],
    mode: langPowershell,
    badge: 'PS',
    color: const Color(0xFF2671BE),
    lineComment: '#',
    blockComment: ('<#', '#>'),
    extensionId: 'smartide.shell',
    run: (c) => '${c.tool('powershell')} -NoProfile -ExecutionPolicy Bypass -File ${RunContext.q(c.file)}',
  ),
  LanguageDef(id: 'bat', name: 'Batch', extensions: ['.bat', '.cmd'], mode: langDos, badge: 'bat', color: const Color(0xFFC1F12E), lineComment: 'REM', extensionId: 'smartide.shell', run: (c) => RunContext.q(c.file)),
  LanguageDef(id: 'shell', name: 'Shell', extensions: ['.sh', '.bash', '.zsh'], fileNames: ['.bashrc', '.zshrc', '.profile'], mode: langBash, badge: 'sh', color: const Color(0xFF4EAA25), lineComment: '#', extensionId: 'smartide.shell', run: (c) => '${c.tool('bash')} ${RunContext.q(c.file)}'),
  LanguageDef(id: 'sql', name: 'SQL', extensions: ['.sql'], mode: langSql, badge: 'sql', color: const Color(0xFFE38C00), lineComment: '--', blockComment: ('/*', '*/')),
  LanguageDef(id: 'yaml', name: 'YAML', extensions: ['.yaml', '.yml'], mode: langYaml, badge: 'yml', color: const Color(0xFFCB171E), lineComment: '#'),
  LanguageDef(id: 'xml', name: 'XML', extensions: ['.xml', '.svg', '.xaml', '.csproj', '.props', '.plist', '.vue'], mode: langXml, badge: 'xml', color: const Color(0xFF0060AC), blockComment: ('<!--', '-->')),
  LanguageDef(id: 'markdown', name: 'Markdown', extensions: ['.md', '.markdown', '.mdx'], mode: langMarkdown, badge: 'M↓', color: const Color(0xFF519ABA), blockComment: ('<!--', '-->'), extensionId: 'smartide.markdown'),
  LanguageDef(id: 'ini', name: 'INI / TOML', extensions: ['.ini', '.toml', '.cfg', '.conf', '.properties', '.env', '.editorconfig'], fileNames: ['.gitconfig', '.env'], mode: langIni, badge: 'cfg', color: const Color(0xFF6D8086), lineComment: '#'),
  LanguageDef(id: 'dockerfile', name: 'Dockerfile', extensions: ['.dockerfile'], fileNames: ['Dockerfile', 'Containerfile'], mode: langDockerfile, badge: 'dk', color: const Color(0xFF2496ED), lineComment: '#'),
  LanguageDef(id: 'makefile', name: 'Makefile', extensions: ['.mk'], fileNames: ['Makefile', 'makefile', 'GNUmakefile'], mode: langMakefile, badge: 'mk', color: const Color(0xFF6D8086), lineComment: '#'),
  LanguageDef(id: 'cmake', name: 'CMake', extensions: ['.cmake'], fileNames: ['CMakeLists.txt'], mode: langCmake, badge: 'cm', color: const Color(0xFF064F8C), lineComment: '#'),
  LanguageDef(id: 'diff', name: 'Diff', extensions: ['.diff', '.patch'], mode: langDiff, badge: '±', color: const Color(0xFF41535B)),
  LanguageDef(id: 'gitignore', name: 'Ignore', extensions: ['.gitignore', '.dockerignore', '.npmignore'], fileNames: ['.gitignore', '.gitattributes', '.dockerignore'], mode: langBash, badge: 'git', color: const Color(0xFFF14E32), lineComment: '#', extensionId: 'smartide.git'),
  LanguageDef(id: 'plaintext', name: 'Plain Text', extensions: ['.txt', '.log', '.csv'], mode: langPlaintext, badge: 'txt', color: const Color(0xFF8A8A8A)),
];

final LanguageDef plainText = languages.firstWhere((l) => l.id == 'plaintext');

LanguageDef languageForPath(String path) {
  final String name = p.basename(path);
  final String ext = p.extension(path).toLowerCase();
  for (final LanguageDef l in languages) {
    if (l.fileNames.contains(name)) return l;
  }
  if (ext.isEmpty) {
    final String dotted = name.toLowerCase();
    for (final LanguageDef l in languages) {
      if (l.extensions.contains(dotted)) return l;
    }
    return plainText;
  }
  for (final LanguageDef l in languages) {
    if (l.extensions.contains(ext)) return l;
  }
  return plainText;
}

LanguageDef? languageById(String id) => languages.where((l) => l.id == id).firstOrNull;
