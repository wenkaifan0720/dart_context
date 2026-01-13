import 'dart:async';

import '../context_builder.dart';
import '../context_formatter.dart';
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
  })  : _llmService = llmService,
        _toolRegistry = toolRegistry;

  final LlmService _llmService;
  final DocToolRegistry _toolRegistry;
  final int maxIterations;

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

  @override
  Future<GeneratedDoc> generateModuleDoc(
    String moduleName,
    List<FolderDocSummary> folders,
  ) async {
    final config = LlmConfig.moduleLevel;
    final systemPrompt = _buildModuleSystemPrompt();
    final userPrompt = _buildModuleUserPrompt(moduleName, folders);

    final messages = <LlmMessage>[
      SystemMessage(systemPrompt),
      UserMessage(userPrompt),
    ];

    return _runAgentLoop(
      messages: messages,
      config: config,
      extractDoc: (content) => _extractModuleDoc(content, moduleName, folders),
    );
  }

  @override
  Future<GeneratedDoc> generateProjectDoc(
    String projectName,
    List<ModuleDocSummary> modules,
  ) async {
    final config = LlmConfig.projectLevel;
    final systemPrompt = _buildProjectSystemPrompt();
    final userPrompt = _buildProjectUserPrompt(projectName, modules);

    final messages = <LlmMessage>[
      SystemMessage(systemPrompt),
      UserMessage(userPrompt),
    ];

    return _runAgentLoop(
      messages: messages,
      config: config,
      extractDoc: (content) =>
          _extractProjectDoc(content, projectName, modules),
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
        final result = await _toolRegistry.executeTool(call.name, call.arguments);
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
You are a technical documentation expert generating docs for a code folder.

Your goal is to create clear, comprehensive documentation that helps developers understand:
1. What this folder contains and its purpose
2. Key classes, functions, and their relationships
3. How this code fits into the larger project
4. Usage examples where appropriate

IMPORTANT GUIDELINES:
- Use smart symbols with scip:// URIs to link to code definitions
- Format: [ClassName](scip://path/to/file.dart/ClassName#)
- Be concise but thorough
- Focus on the "why" not just the "what"
- Include any important architectural decisions
- Document public API thoroughly, internal details briefly

You have access to tools to explore the codebase. Use them to gather information
before generating documentation. The `get_public_api` tool is especially useful
for understanding interfaces without reading entire files.

When you have gathered enough information, generate the documentation as markdown.
Start with a title (# Folder Name), then include sections for Overview, Key Components,
Usage, and Dependencies as appropriate.
''';

  String _buildModuleSystemPrompt() => '''
You are a technical documentation expert generating docs for a code module.

A module is a logical grouping of folders that together implement a feature or domain.

Your goal is to create documentation that:
1. Explains the module's overall purpose and scope
2. Shows how the component folders work together
3. Provides architectural overview
4. Documents key entry points and patterns

Use smart symbols with scip:// URIs to link to specific code.
Structure the doc with: Overview, Architecture, Components, Usage, and Integration sections.
''';

  String _buildProjectSystemPrompt() => '''
You are a technical documentation expert generating project-level documentation.

This is the top-level documentation that gives developers an overview of the entire project.

Your goal is to create documentation that:
1. Explains the project's purpose and key features
2. Describes the high-level architecture
3. Shows how modules relate to each other
4. Provides guidance for new developers

Structure: Overview, Architecture, Modules, Getting Started, and Contributing sections.
Use smart symbols to link to specific code when relevant.
''';

  // ===== User Prompts =====

  String _buildFolderUserPrompt(DocContext context) {
    final formatter = ContextFormatter();
    final yaml = formatter.formatAsYaml(context);

    return '''
Generate documentation for the following folder:

$yaml

Use the available tools to gather any additional information you need.
When ready, output the final documentation in markdown format.
''';
  }

  String _buildModuleUserPrompt(
    String moduleName,
    List<FolderDocSummary> folders,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('Generate documentation for module: $moduleName');
    buffer.writeln();
    buffer.writeln('Component folders:');
    for (final folder in folders) {
      buffer.writeln('## ${folder.path}');
      if (folder.summary != null) {
        buffer.writeln('Summary: ${folder.summary}');
      }
      buffer.writeln();
      // Include first ~500 chars of doc
      final preview = folder.content.length > 500
          ? '${folder.content.substring(0, 500)}...'
          : folder.content;
      buffer.writeln(preview);
      buffer.writeln();
    }

    return buffer.toString();
  }

  String _buildProjectUserPrompt(
    String projectName,
    List<ModuleDocSummary> modules,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('Generate project documentation for: $projectName');
    buffer.writeln();
    buffer.writeln('Modules:');
    for (final module in modules) {
      buffer.writeln('## ${module.name}');
      if (module.summary != null) {
        buffer.writeln('Summary: ${module.summary}');
      }
      buffer.writeln();
      final preview = module.content.length > 500
          ? '${module.content.substring(0, 500)}...'
          : module.content;
      buffer.writeln(preview);
      buffer.writeln();
    }

    return buffer.toString();
  }

  // ===== Doc Extraction =====

  GeneratedDoc _extractFolderDoc(String content, DocContext context) {
    final smartSymbols = _extractSmartSymbols(content);
    final title = _extractTitle(content);
    final summary = _extractSummary(content);

    return GeneratedDoc(
      content: content,
      smartSymbols: smartSymbols,
      title: title,
      summary: summary,
    );
  }

  GeneratedDoc _extractModuleDoc(
    String content,
    String moduleName,
    List<FolderDocSummary> folders,
  ) {
    final smartSymbols = _extractSmartSymbols(content);
    // Also include symbols from folder docs
    for (final folder in folders) {
      smartSymbols.addAll(folder.smartSymbols);
    }

    return GeneratedDoc(
      content: content,
      smartSymbols: smartSymbols.toSet().toList(),
      title: '$moduleName Module',
      summary: _extractSummary(content),
    );
  }

  GeneratedDoc _extractProjectDoc(
    String content,
    String projectName,
    List<ModuleDocSummary> modules,
  ) {
    final smartSymbols = _extractSmartSymbols(content);
    // Also include symbols from module docs
    for (final module in modules) {
      smartSymbols.addAll(module.smartSymbols);
    }

    return GeneratedDoc(
      content: content,
      smartSymbols: smartSymbols.toSet().toList(),
      title: projectName,
      summary: _extractSummary(content),
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
