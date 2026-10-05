import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

/// Starter project templates offered on the welcome page.
class ProjectTemplate {
  const ProjectTemplate(this.id, this.name, this.badge, this.color, this.files, this.mainFile, this.description);

  final String id;
  final String name;
  final String badge;
  final Color color;

  /// Relative path -> content. `{{name}}` is replaced with the project name.
  final Map<String, String> files;
  final String mainFile;
  final String description;

  Future<String> create(String parent, String name) async {
    final String root = p.join(parent, name);
    await Directory(root).create(recursive: true);
    final String safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    for (final MapEntry<String, String> e in files.entries) {
      final File f = File(p.join(root, e.key.replaceAll('{{name}}', safe)));
      await f.parent.create(recursive: true);
      await f.writeAsString(e.value.replaceAll('{{name}}', safe).replaceAll('{{title}}', name));
    }
    return root;
  }
}

const String _gitignore = '''
# Build output
build/
dist/
bin/
obj/
target/
*.exe
*.o

# Dependencies
node_modules/
.venv/
venv/
__pycache__/

# Editors
.vscode/
.idea/
''';

const List<ProjectTemplate> projectTemplates = [
  ProjectTemplate('python', 'Python', 'py', Color(0xFF3B82C4), {
    'main.py': '''"""{{title}} — created with SmartIDE."""


def greet(name: str) -> str:
    return f"Hello, {name}!"


def main() -> None:
    name = input("What is your name? ")
    print(greet(name or "World"))


if __name__ == "__main__":
    main()
''',
    'requirements.txt': '',
    'README.md': '# {{title}}\n\nRun with **F5** in SmartIDE or `python main.py`.\n',
    '.gitignore': _gitignore,
  }, 'main.py', 'Script with input/output'),
  ProjectTemplate('cpp', 'C++', 'C++', Color(0xFF00599C), {
    'main.cpp': '''#include <iostream>
#include <string>
#include <vector>

int main() {
    std::string name;
    std::cout << "What is your name? ";
    std::getline(std::cin, name);
    std::cout << "Hello, " << (name.empty() ? "World" : name) << "!" << std::endl;

    std::vector<int> numbers{5, 3, 8, 1};
    int sum = 0;
    for (int n : numbers) sum += n;
    std::cout << "Sum: " << sum << std::endl;
    return 0;
}
''',
    'README.md': '# {{title}}\n\nPress **F5** to compile with g++ and run.\n',
    '.gitignore': _gitignore,
  }, 'main.cpp', 'Console app with g++'),
  ProjectTemplate('c', 'C', 'C', Color(0xFF5C8DBC), {
    'main.c': '''#include <stdio.h>

int main(void) {
    char name[64];
    printf("What is your name? ");
    if (scanf("%63s", name) != 1) return 1;
    printf("Hello, %s!\\n", name);
    return 0;
}
''',
    '.gitignore': _gitignore,
  }, 'main.c', 'Console app with gcc'),
  ProjectTemplate('csharp', 'C# (.NET)', 'C#', Color(0xFF9B4F96), {
    '{{name}}.csproj': '''<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>

</Project>
''',
    'Program.cs': '''Console.Write("What is your name? ");
var name = Console.ReadLine();
Console.WriteLine(\$"Hello, {(string.IsNullOrWhiteSpace(name) ? "World" : name)}!");
''',
    '.gitignore': _gitignore,
  }, 'Program.cs', 'dotnet console project'),
  ProjectTemplate('go', 'Go', 'go', Color(0xFF00ADD8), {
    'go.mod': 'module {{name}}\n\ngo 1.24\n',
    'main.go': '''package main

import (
\t"bufio"
\t"fmt"
\t"os"
\t"strings"
)

func main() {
\tfmt.Print("What is your name? ")
\treader := bufio.NewReader(os.Stdin)
\tname, _ := reader.ReadString('\\n')
\tname = strings.TrimSpace(name)
\tif name == "" {
\t\tname = "World"
\t}
\tfmt.Printf("Hello, %s!\\n", name)
}
''',
    '.gitignore': _gitignore,
  }, 'main.go', 'Go module'),
  ProjectTemplate('web', 'Web (HTML/CSS/JS)', '<>', Color(0xFFE44D26), {
    'index.html': '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{{title}}</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <main class="card">
    <h1>{{title}}</h1>
    <p>Edit <code>index.html</code> and save — Live Server reloads instantly.</p>
    <button id="btn">Click me</button>
    <p id="count">0 clicks</p>
  </main>
  <script src="script.js"></script>
</body>
</html>
''',
    'style.css': ''':root {
  --bg: #faf9f5;
  --fg: #2b2a27;
  --accent: #c96442;
}

* { box-sizing: border-box; }

body {
  margin: 0;
  min-height: 100vh;
  display: grid;
  place-items: center;
  background: var(--bg);
  color: var(--fg);
  font-family: "Segoe UI", system-ui, sans-serif;
}

.card {
  padding: 40px 48px;
  border-radius: 16px;
  background: white;
  box-shadow: 0 10px 40px rgba(0, 0, 0, 0.08);
  text-align: center;
}

h1 { font-family: Georgia, serif; font-weight: 400; }

button {
  padding: 10px 22px;
  border: 0;
  border-radius: 10px;
  background: var(--accent);
  color: white;
  font-size: 15px;
  cursor: pointer;
}
''',
    'script.js': '''const btn = document.getElementById('btn');
const count = document.getElementById('count');
let clicks = 0;

btn.addEventListener('click', () => {
  clicks++;
  count.textContent = `\${clicks} click\${clicks === 1 ? '' : 's'}`;
});
''',
    '.gitignore': _gitignore,
  }, 'index.html', 'Static site + Live Server'),
  ProjectTemplate('node', 'Node.js', 'JS', Color(0xFF68A063), {
    'package.json': '{\n  "name": "{{name}}",\n  "version": "1.0.0",\n  "type": "module",\n  "main": "index.js",\n  "scripts": {\n    "start": "node index.js"\n  }\n}\n',
    'index.js': '''import { createServer } from 'node:http';

const server = createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('Hello from {{title}}!\\n');
});

server.listen(3000, () => console.log('Server running at http://localhost:3000'));
''',
    '.gitignore': _gitignore,
  }, 'index.js', 'HTTP server'),
  ProjectTemplate('rust', 'Rust', 'rs', Color(0xFFDEA584), {
    'Cargo.toml': '[package]\nname = "{{name}}"\nversion = "0.1.0"\nedition = "2024"\n\n[dependencies]\n',
    'src/main.rs': '''use std::io;

fn main() {
    println!("What is your name?");
    let mut name = String::new();
    io::stdin().read_line(&mut name).expect("failed to read line");
    let name = name.trim();
    println!("Hello, {}!", if name.is_empty() { "World" } else { name });
}
''',
    '.gitignore': _gitignore,
  }, 'src/main.rs', 'Cargo binary'),
  ProjectTemplate('java', 'Java', 'J', Color(0xFFE76F00), {
    'Main.java': '''import java.util.Scanner;

public class Main {
    public static void main(String[] args) {
        Scanner in = new Scanner(System.in);
        System.out.print("What is your name? ");
        String name = in.nextLine().trim();
        System.out.println("Hello, " + (name.isEmpty() ? "World" : name) + "!");
    }
}
''',
    '.gitignore': _gitignore,
  }, 'Main.java', 'Single-file program'),
];
