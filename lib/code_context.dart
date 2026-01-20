/// Language-agnostic semantic code intelligence.
///
/// Query your codebase with a simple DSL:
/// ```dart
/// // Auto-detect language from project files
/// final context = await CodeContext.open('/path/to/project');
///
/// // Or specify a binding explicitly
/// final context = await CodeContext.open(
///   '/path/to/project',
///   binding: DartBinding(),
/// );
///
/// // Find definition
/// final result = await context.query('def AuthRepository');
///
/// // Find references
/// final refs = await context.query('refs login');
///
/// // Load dependencies for cross-package queries
/// await context.loadDependencies();
///
/// // Query with full dependency support
/// final hierarchy = await context.query('hierarchy MyWidget');
/// ```
///
/// ## Supported Languages
///
/// - Dart (via `DartBinding` from `dart_binding` package)
/// - More languages coming soon...
///
/// ## Works with any folder structure
///
/// The unified architecture works for:
/// - Single packages
/// - Melos mono repos
/// - Dart pub workspaces
/// - Any folder with multiple packages
library;

// Main entry point
export 'src/code_context.dart';

// Re-export scip_server package (language-agnostic core)
export 'package:scip_server/scip_server.dart'
    show
        // Index types
        ScipIndex,
        SymbolInfo,
        OccurrenceInfo,
        GrepMatchInfo,
        IndexProvider,
        ReferenceWithSource,
        // Query engine
        QueryExecutor,
        ScipQuery,
        QueryAction,
        ParsedPattern,
        PatternType,
        // Result types
        QueryResult,
        DefinitionResult,
        DefinitionMatch,
        ReferencesResult,
        ReferenceMatch,
        AggregatedReferencesResult,
        SymbolReferences,
        MembersResult,
        HierarchyResult,
        SearchResult,
        SourceResult,
        SignatureResult,
        CallGraphResult,
        ImportsResult,
        FilesResult,
        FileSymbolsResult,
        StatsResult,
        PipelineResult,
        NotFoundResult,
        ErrorResult,
        // Language binding
        LanguageBinding,
        LanguageContext,
        DiscoveredPackage,
        PackageIndexer,
        IndexUpdate,
        InitialIndexUpdate,
        FileUpdatedUpdate,
        FileRemovedUpdate,
        IndexErrorUpdate,
        // Protocol server
        ScipServer,
        ScipMethod,
        JsonRpcRequest,
        JsonRpcResponse,
        JsonRpcError,
        QueryResponse,
        QueryParams,
        InitializeParams,
        FileChangeParams,
        StatusResult;

// Re-export dart_binding package (Dart-specific)
export 'package:dart_binding/dart_binding.dart'
    show
        // Main binding
        DartBinding,
        DartLanguageContext,
        DartPackageIndexer,
        RootWatcher,
        // Indexing
        IncrementalScipIndexer,
        IndexCache,
        ExternalIndexBuilder,
        IndexResult,
        BatchIndexResult,
        PackageIndexResult,
        FlutterIndexResult,
        CachedIndexUpdate,
        IncrementalIndexUpdate,
        // Package management
        PackageRegistry,
        PackageRegistryProvider,
        PackageRegistryProviderExtension,
        LocalPackageIndex,
        ExternalPackageIndex,
        ExternalPackageType,
        DependencyLoadResult,
        IndexScope,
        // Discovery
        LocalPackage,
        DiscoveryResult,
        PackageDiscovery,
        // Cache
        CachePaths,
        // Adapters
        AnalyzerAdapter,
        FileChange,
        FileChangeType,
        HologramAnalyzerAdapter,
        // Utilities
        DependencySource,
        ResolvedPackage,
        parsePackageConfig,
        parsePackageConfigSync,
        dartContextVersion,
        manifestVersion;

// ─────────────────────────────────────────────────────────────────────────────
// Architecture Notes
// ─────────────────────────────────────────────────────────────────────────────

// This package is structured as follows:
//
// packages/
// ├── scip_server/              # Language-agnostic SCIP query engine
// │   ├── ScipIndex             # In-memory SCIP index
// │   ├── QueryExecutor         # DSL query execution
// │   ├── LanguageBinding       # Interface for language implementations
// │   ├── LanguageContext       # Abstract context interface
// │   └── ScipServer            # JSON-RPC protocol server
// │
// └── dart_binding/             # Dart-specific implementation
//     ├── DartBinding           # LanguageBinding implementation
//     ├── DartLanguageContext   # LanguageContext implementation
//     ├── IncrementalScipIndexer # Incremental Dart indexer
//     ├── PackageRegistry       # Multi-package management
//     └── PackageDiscovery      # Pubspec.yaml discovery
//
// The root package (code_context) provides:
// - CodeContext: High-level API using LanguageBinding
// - MCP server integration
