# Architecture

## Overview

code_context provides lightweight semantic code intelligence for Dart projects. It uses SCIP (Semantic Code Intelligence Protocol) for standardized code indexing.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           CodeContext                                   │
│  Entry point: open(), query(), dispose()                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────────────┐│
│  │ LLM / Agent  │────▶│ Query String │────▶│    QueryExecutor         ││
│  │              │     │ "refs login" │     │                          ││
│  └──────────────┘     └──────────────┘     │  parse() → execute()     ││
│                                            └────────────┬─────────────┘│
│                                                         │              │
│                                                         ▼              │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                     PackageRegistry                              │  │
│  │  Local packages (mutable) + External packages (cached)          │  │
│  │  Cross-package symbol search, dependency resolution             │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                  │                                     │
│              ┌───────────────────┼───────────────────┐                 │
│              ▼                   ▼                   ▼                 │
│  ┌───────────────────┐  ┌───────────────┐  ┌────────────────────────┐ │
│  │ LocalPackageIndex │  │ ScipIndex     │  │ ExternalPackageIndex   │ │
│  │ + Indexer (live)  │  │ O(1) lookups  │  │ SDK/Flutter/pub (cached)│ │
│  └───────────────────┘  └───────────────┘  └────────────────────────┘ │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Package Structure (Monorepo)

The project is organized as a Dart pub workspace:

```
code_context/
├── packages/
│   ├── scip_server/          # Language-agnostic SCIP protocol core
│   │   ├── lib/src/
│   │   │   ├── index/        # ScipIndex, IndexProvider
│   │   │   ├── query/        # QueryParser, QueryExecutor, QueryResult
│   │   │   ├── protocol/     # JSON-RPC protocol layer
│   │   │   └── language_binding.dart
│   │   └── pubspec.yaml
│   │
│   └── dart_binding/         # Dart-specific implementation
│       ├── lib/src/
│       │   ├── adapters/     # Analyzer adapters
│       │   ├── cache/        # Cache path management
│       │   └── ...           # Incremental indexer, package discovery
│       └── pubspec.yaml
│
├── lib/                      # Root package (code_context)
│   ├── code_context.dart     # Re-exports for public API
│   └── src/
│       ├── code_context.dart # Main CodeContext class
│       └── mcp/              # MCP server support
│
├── bin/
│   ├── code_context.dart     # CLI entry point
│   └── mcp_server.dart       # MCP server entry point
│
└── pubspec.yaml              # Workspace root
```

## Core Components

### scip_server (Language-Agnostic)

| Component | Description |
|-----------|-------------|
| `ScipIndex` | In-memory index with O(1) symbol lookups |
| `QueryParser` | Parses DSL queries into structured commands |
| `QueryExecutor` | Executes queries against an index |
| `IndexProvider` | Abstract interface for cross-index operations |
| `LanguageBinding` | Interface for language-specific implementations |

### dart_binding (Dart-Specific)

| Component | Description |
|-----------|-------------|
| `DartBinding` | Implements `LanguageBinding` for Dart |
| `IncrementalScipIndexer` | File-watching incremental indexer |
| `PackageRegistry` | Manages local + external package indexes |
| `PackageDiscovery` | Discovers packages in monorepos |
| `ExternalIndexBuilder` | Pre-computes indexes for SDK/dependencies |
| `FlutterNavigationDetector` | Detects navigation patterns (go_router, Navigator, etc.) |
| `DartSymbolClassifier` | Classifies symbols by layer/feature using SCIP data |
| `DartNavigationChainExtractor` | Extracts call chains using Dart Analyzer AST |

## How It Works

### Indexing Flow

1. **Cache Check**: On `open()`, looks for valid cache in `.code_context/` directory
2. **Initial/Incremental Index**: Full scan if no cache, or only changed files if cache exists
3. **File Watching**: Uses filesystem events to detect changes
4. **Incremental Updates**: Only re-analyzes changed files (via SHA-256 hash comparison)
5. **Cache Persistence**: Saves index to disk after updates for fast subsequent startups

### Query Flow

1. **Parse**: DSL string → `ScipQuery` object
2. **Execute**: Query runs against `ScipIndex` (or `IndexProvider` for cross-package)
3. **Format**: Results formatted as text or JSON

### Caching

The index is cached in `.code_context/` within your project:

```
your_project/
└── .code_context/
    ├── index.scip         # Serialized SCIP protobuf index
    └── manifest.json      # File hashes for cache validation
```

Global pre-computed indexes are stored in `~/.code_context/`:

```
~/.code_context/
├── sdk/
│   └── 3.2.0/index.scip             # Dart SDK
├── flutter/
│   └── 3.32.0/flutter/index.scip    # Flutter packages
├── hosted/
│   ├── collection-1.18.0/index.scip # Pub packages
│   └── analyzer-6.3.0/index.scip
└── git/
    └── fluxon-bfef6c5e/index.scip   # Git dependencies
```

## Performance

| Metric | Value |
|--------|-------|
| Initial indexing | ~10-15s for 85 files |
| Cached startup | ~300ms (35x faster) |
| Incremental update | ~100-200ms per file |
| Query execution | <10ms |
| Cache size | ~2.5MB for 85 files |

## Design Goals

1. **Lightweight**: Minimal dependencies, fast startup
2. **Incremental**: Only re-index changed files
3. **AI-Friendly**: DSL designed for LLM/agent consumption
4. **Extensible**: Language-agnostic core with pluggable bindings
5. **SCIP-Compatible**: Uses standard SCIP format for interoperability

