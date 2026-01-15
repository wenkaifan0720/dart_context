import 'dart:async';

import '../context_builder.dart';
import '../llm_interface.dart';
import 'doc_tools.dart';
import 'llm_service.dart';

/// Agentic documentation generator.
///
/// This agent generates documentation for folders by:
/// 1. Receiving initial context about the folder
/// 2. Using tools to explore and understand the code
/// 3. Generating comprehensive documentation with smart symbols
class DocGenerationAgent implements DocGenerator {
  DocGenerationAgent({
    required LlmService llmService,
    required DocToolRegistry toolRegistry,
    this.maxIterations = 10,
    this.verbose = false,
    this.onLog,
  })  : _llmService = llmService,
        _toolRegistry = toolRegistry;

  final LlmService _llmService;
  final DocToolRegistry _toolRegistry;
  final int maxIterations;
  final bool verbose;
  final void Function(String)? onLog;

  // Track token usage
  int _inputTokens = 0;
  int _outputTokens = 0;

  /// Get total token usage.
  (int input, int output) get tokenUsage => (_inputTokens, _outputTokens);

  @override
  Future<GeneratedDoc> generateFolderDoc(DocContext context) async {
    final config = _getConfigForFolder(context);
    final systemPrompt = _buildFolderSystemPrompt();
    final userPrompt = _buildFolderUserPrompt(context);

    final messages = <LlmMessage>[
      SystemMessage(systemPrompt),
      UserMessage(userPrompt),
    ];

    return _runAgentLoop(
      messages: messages,
      config: config,
      extractDoc: (content) => _extractFolderDoc(content, context),
    );
  }

  /// Run the agent loop with tool calling.
  Future<GeneratedDoc> _runAgentLoop({
    required List<LlmMessage> messages,
    required LlmConfig config,
    required GeneratedDoc Function(String content) extractDoc,
  }) async {
    var iterations = 0;

    while (iterations < maxIterations) {
      iterations++;

      final response = await _llmService.chat(
        messages: messages,
        config: config,
        tools: _toolRegistry.tools,
      );

      _inputTokens += response.inputTokens;
      _outputTokens += response.outputTokens;

      // If no tool calls, we have the final response
      if (!response.hasToolCalls) {
        final content = response.content ?? '';
        return extractDoc(content);
      }

      // Handle tool calls
      messages.add(AssistantMessage(
        content: response.content,
        toolCalls: response.toolCalls,
      ));

      final toolResults = <LlmToolResult>[];
      for (final call in response.toolCalls) {
        _log('[Tool Call] ${call.name}(${call.arguments})');
        final result =
            await _toolRegistry.executeTool(call.name, call.arguments);
        _log('[Tool Result] ${result.length} chars');
        toolResults.add(LlmToolResult(
          toolCallId: call.id,
          content: result,
        ));
      }

      messages.add(ToolResultsMessage(toolResults));
    }

    // Max iterations reached - generate with current context
    final response = await _llmService.chat(
      messages: [
        ...messages,
        const UserMessage(
          'Please generate the documentation now with the information you have gathered.',
        ),
      ],
      config: config,
      tools: [], // No tools - force text response
    );

    _inputTokens += response.inputTokens;
    _outputTokens += response.outputTokens;

    return extractDoc(response.content ?? '');
  }

  // ===== Config Selection =====

  LlmConfig _getConfigForFolder(DocContext context) {
    // Count total lines/complexity
    final fileCount = context.current.files.length;
    final symbolCount = context.current.files
        .fold<int>(0, (sum, f) => sum + f.publicApi.length);

    // Simple heuristic: more complex folders get higher token limits
    if (symbolCount > 50 || fileCount > 10) {
      return LlmConfig.moduleLevel; // More tokens for complex folders
    }
    return LlmConfig.folderLevel;
  }

  // ===== System Prompts =====

  String _buildFolderSystemPrompt() => '''
You are writing documentation for a code folder. Write it as you would any good technical documentation - clear, self-contained, and useful for both humans and AI agents trying to understand this code.

TOOLS AVAILABLE:
- `list_folder` - see files and subfolders
- `get_public_api` - get the public API of a specific .dart file
- `read_subfolder_doc` - read existing documentation for subfolders (marked [documented] in list_folder)
- `read_file` - read source code when needed

For large folders, sample representative files rather than reading everything.

UNIQUE CAPABILITIES:
- You can read existing docs from subfolders and synthesize higher-level overviews
- Link to subfolder docs: [Components](doc://lib/src/components)
- Link to code with smart symbols: [ClassName](scip://path/to/file.dart/ClassName#)

Write the documentation in markdown.
''';

  // ===== User Prompts =====

  String _buildFolderUserPrompt(DocContext context) {
    // Minimal prompt - let the agent explore using tools
    // Don't pass the full context upfront (can exceed token limits for large folders)
    final folderPath = context.current.path;
    final fileCount = context.current.files.length;
    final internalDeps = context.current.internalDeps.take(5).toList();

    final buffer = StringBuffer();
    buffer.writeln('Generate documentation for folder: **$folderPath**');
    buffer.writeln();
    buffer.writeln('Quick stats:');
    buffer.writeln('- Files in this folder: $fileCount');
    if (internalDeps.isNotEmpty) {
      buffer.writeln('- Key dependencies: ${internalDeps.join(", ")}');
    }
    buffer.writeln();
    buffer.writeln('Use the available tools to explore this folder:');
    buffer.writeln('1. `list_folder` - see files and subfolders');
    buffer.writeln('2. `get_public_api` - get API for a specific .dart file');
    buffer
        .writeln('3. `read_subfolder_doc` - read documentation for subfolders');
    buffer.writeln('4. `read_file` - read source code when needed');
    buffer.writeln();
    buffer.writeln(
        'For large folders with many files, sample representative files to understand patterns.');
    buffer.writeln(
        'When ready, output the final documentation in markdown format.');

    return buffer.toString();
  }

  // ===== Helpers =====

  void _log(String message) {
    if (verbose) {
      onLog?.call(message);
      print(message);
    }
  }

  /// Strip LLM thinking/meta-commentary from generated content.
  ///
  /// Removes lines that look like:
  /// - "Now I have enough information..."
  /// - "Let me generate..."
  /// - Other conversational filler
  String _stripThinking(String content) {
    final lines = content.split('\n');
    final filtered = <String>[];

    for (final line in lines) {
      final trimmed = line.trim().toLowerCase();

      // Skip thinking lines
      if (trimmed.startsWith('now i ') ||
          trimmed.startsWith('let me ') ||
          trimmed.startsWith('i will ') ||
          trimmed.startsWith('i can ') ||
          trimmed.startsWith('i have ') ||
          trimmed.startsWith('i need ') ||
          trimmed.contains('enough information') ||
          trimmed.contains('generate comprehensive')) {
        continue;
      }

      filtered.add(line);
    }

    // Remove leading empty lines
    while (filtered.isNotEmpty && filtered.first.trim().isEmpty) {
      filtered.removeAt(0);
    }

    return filtered.join('\n');
  }

  // ===== Doc Extraction =====

  GeneratedDoc _extractFolderDoc(String content, DocContext context) {
    final cleaned = _stripThinking(content);
    final smartSymbols = _extractSmartSymbols(cleaned);
    final title = _extractTitle(cleaned);
    final summary = _extractSummary(cleaned);

    return GeneratedDoc(
      content: cleaned,
      smartSymbols: smartSymbols,
      title: title,
      summary: summary,
    );
  }

  /// Extract scip:// URIs from content.
  List<String> _extractSmartSymbols(String content) {
    final regex = RegExp(r'scip://[^\s\)>\]]+');
    return regex.allMatches(content).map((m) => m.group(0)!).toList();
  }

  /// Extract title from markdown content.
  String? _extractTitle(String content) {
    final match = RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(content);
    return match?.group(1);
  }

  /// Extract first paragraph as summary.
  String? _extractSummary(String content) {
    final lines = content.split('\n');
    final buffer = StringBuffer();

    var inParagraph = false;
    for (final line in lines) {
      // Skip title
      if (line.startsWith('#')) continue;

      // Skip empty lines before paragraph
      if (!inParagraph && line.trim().isEmpty) continue;

      // End paragraph on empty line
      if (inParagraph && line.trim().isEmpty) break;

      inParagraph = true;
      buffer.write(line);
      buffer.write(' ');
    }

    final summary = buffer.toString().trim();
    if (summary.isEmpty) return null;

    // Truncate if too long
    if (summary.length > 200) {
      return '${summary.substring(0, 197)}...';
    }
    return summary;
  }
}
