import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/settings.dart';

class AssistantModel {
  const AssistantModel(this.id, this.name, this.note, {this.supportsEffort = true, this.supportsFallbacks = true});

  final String id;
  final String name;
  final String note;
  final bool supportsEffort;
  final bool supportsFallbacks;
}

const List<AssistantModel> assistantModels = [
  AssistantModel('claude-opus-5-5', 'Claude Opus 5.5', 'Best default for coding'),
  AssistantModel('claude-sonnet-5-5', 'Claude Sonnet 5.5', 'Fast everyday coding'),
  AssistantModel('claude-fable-5-1', 'Claude Fable 5.1', 'Most capable, slower', supportsEffort: true),
  AssistantModel('claude-haiku-4-5', 'Claude Haiku 4.5', 'Quickest & cheapest', supportsEffort: false, supportsFallbacks: false),
];

class ChatMessage {
  ChatMessage(this.role, this.text, {this.context});

  final String role; // 'user' | 'assistant'
  String text;

  /// Short description of attached context (e.g. "main.py · lines 10-42").
  final String? context;
  bool streaming = false;
  bool error = false;

  /// Text actually sent to the API (prompt plus attached code).
  String? apiText;
}

/// Chat assistant backed by the Claude Messages API (raw HTTP + SSE, since
/// there is no official Dart SDK).
class AssistantService extends ChangeNotifier {
  AssistantService(this.settings);

  final Settings settings;
  final List<ChatMessage> messages = [];
  bool busy = false;
  HttpClient? _client;
  bool _cancelled = false;

  static const String _endpoint = 'https://api.anthropic.com/v1/messages';
  static const String _system = 'You are SmartIDE Assistant, an expert pair programmer embedded in the SmartIDE code editor on the '
      "user's computer. Be concise and practical. When you show code, use fenced Markdown code blocks with a language tag so the "
      'user can insert it into the editor. When the user attaches a file or selection, ground your answer in that code.';

  bool get hasKey => settings.aiApiKey.trim().isNotEmpty;

  AssistantModel get model => assistantModels.firstWhere((m) => m.id == settings.aiModel, orElse: () => assistantModels.first);

  void clear() {
    cancel();
    messages.clear();
    notifyListeners();
  }

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
    _client = null;
    if (busy) {
      busy = false;
      if (messages.isNotEmpty && messages.last.streaming) messages.last.streaming = false;
      notifyListeners();
    }
  }

  Future<void> send(String prompt, {String? contextLabel, String? contextCode, String? language}) async {
    if (busy || prompt.trim().isEmpty) return;
    final String content = contextCode == null
        ? prompt
        : '$prompt\n\n<attached_code ${contextLabel == null ? '' : 'source="$contextLabel"'}>\n```${language ?? ''}\n$contextCode\n```\n</attached_code>';
    messages.add(ChatMessage('user', prompt, context: contextLabel)..apiText = content);
    final ChatMessage reply = ChatMessage('assistant', '')..streaming = true;
    messages.add(reply);
    busy = true;
    _cancelled = false;
    notifyListeners();

    final AssistantModel m = model;
    final Map<String, dynamic> body = {
      'model': m.id,
      'max_tokens': 32000,
      'stream': true,
      'system': _system,
      if (m.supportsEffort) 'output_config': {'effort': 'medium'},
      if (m.supportsFallbacks) 'fallbacks': 'default',
      'messages': [
        for (final ChatMessage msg in messages)
          if (msg != reply && !msg.error && (msg.role == 'user' || msg.text.isNotEmpty))
            {'role': msg.role, 'content': msg.apiText ?? msg.text},
      ],
    };

    try {
      _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final HttpClientRequest req = await _client!.postUrl(Uri.parse(_endpoint));
      req.headers
        ..set('content-type', 'application/json')
        ..set('x-api-key', settings.aiApiKey.trim())
        ..set('anthropic-version', '2023-06-01');
      if (m.supportsFallbacks) req.headers.set('anthropic-beta', 'server-side-fallback-2026-07-01');
      req.add(utf8.encode(jsonEncode(body)));
      final HttpClientResponse res = await req.close();
      if (res.statusCode != 200) {
        final String err = await res.transform(utf8.decoder).join();
        _fail(reply, _describeError(res.statusCode, err));
        return;
      }
      String event = '';
      await for (final String line in res.transform(utf8.decoder).transform(const LineSplitter())) {
        if (_cancelled) break;
        if (line.startsWith('event:')) {
          event = line.substring(6).trim();
          continue;
        }
        if (!line.startsWith('data:')) continue;
        final Map<String, dynamic> data = jsonDecode(line.substring(5).trim()) as Map<String, dynamic>;
        switch (event.isEmpty ? data['type'] : event) {
          case 'content_block_delta':
            final dynamic delta = data['delta'];
            if (delta is Map && delta['type'] == 'text_delta') {
              reply.text += delta['text'] as String;
              notifyListeners();
            }
          case 'message_delta':
            final dynamic stop = (data['delta'] as Map?)?['stop_reason'];
            if (stop == 'refusal') {
              reply.text += '\n\n_The model declined to answer this request._';
            } else if (stop == 'max_tokens') {
              reply.text += '\n\n_(Answer truncated — ask me to continue.)_';
            }
          case 'error':
            _fail(reply, 'API error: ${(data['error'] as Map?)?['message'] ?? data}');
            return;
        }
      }
    } catch (e) {
      if (!_cancelled) _fail(reply, 'Network error: $e');
      return;
    } finally {
      _client?.close();
      _client = null;
    }
    reply.streaming = false;
    busy = false;
    notifyListeners();
  }

  void _fail(ChatMessage reply, String message) {
    reply
      ..text = message
      ..error = true
      ..streaming = false;
    busy = false;
    notifyListeners();
  }

  static String _describeError(int status, String body) {
    String detail = body;
    try {
      final dynamic j = jsonDecode(body);
      detail = '${j['error']?['message'] ?? body}';
    } catch (_) {}
    return switch (status) {
      401 => 'Invalid API key. Open Settings → Assistant and paste a key from console.anthropic.com.',
      402 => 'Billing issue on your Anthropic account: $detail',
      403 => 'Permission denied: $detail',
      429 => 'Rate limited — please wait a moment and try again.',
      529 => 'Claude is overloaded right now. Please retry shortly.',
      _ => 'Error $status: $detail',
    };
  }
}
