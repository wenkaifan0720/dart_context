# Getting Started

## Installation

### As a Library

```bash
dart pub add code_context
```

### As a CLI Tool

```bash
dart pub global activate code_context
```

## Quick Start

### Library Usage

```dart
import 'package:code_context/code_context.dart';

void main() async {
  // Open a project
  final context = await CodeContext.open('/path/to/project');

  // Query with DSL
  final result = await context.query('def AuthRepository');
  print(result.toText());

  // Find references
  final refs = await context.query('refs login');
  print(refs.toText());

  // Get class members
  final members = await context.query('members MyClass');
  print(members.toJson());

  // Watch for updates
  context.updates.listen((update) {
    print('Index updated: $update');
  });

  // Cleanup
  await context.dispose();
}
```

### CLI Usage

```bash
# Find definition
code_context def AuthRepository

# Find references
code_context refs login

# Get class members
code_context members MyClass

# Search with filters
code_context "find Auth* kind:class"
code_context "find * kind:method in:lib/auth/"

# Interactive mode
code_context -i

# Watch mode (shows file changes)
code_context -w

# Watch mode with auto-rerun query
code_context -w "find * kind:class"

# JSON output
code_context -f json refs login

# Force full re-index (skip cache)
code_context --no-cache stats
```

## Next Steps

- [Query DSL Reference](query-dsl.md) - Full command reference
- [Architecture](architecture.md) - How it works
- [Auto-Generated Docs](auto-docs.md) - Generate architecture and navigation docs
- [MCP Integration](mcp-integration.md) - Using with Cursor/AI agents
- [Monorepo Support](monorepo.md) - Multi-package workspaces

