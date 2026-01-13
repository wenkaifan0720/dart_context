/// Language-agnostic SCIP query engine and protocol server.
///
/// This library provides:
/// - [ScipIndex] - In-memory representation of a SCIP index
/// - [QueryExecutor] - Execute DSL queries against the index
/// - [LanguageBinding] - Interface for language-specific implementations
/// - [IndexProvider] - Interface for cross-package queries
/// - [ScipServer] - JSON-RPC protocol server
/// - Documentation infrastructure for auto-generated docs
library scip_server;

// Core index types
export 'src/index/scip_index.dart';
export 'src/index/index_provider.dart';

// Query engine
export 'src/query/query_parser.dart';
export 'src/query/query_executor.dart';
export 'src/query/query_result.dart';

// Classification and navigation
export 'src/classification/classification_binding.dart';
export 'src/classification/classifier.dart';
export 'src/classification/navigation.dart';
export 'src/classification/types.dart';

// Language binding interface
export 'src/language_binding.dart';

// Protocol server
export 'src/protocol/protocol.dart';
export 'src/protocol/json_rpc_server.dart';

// Documentation infrastructure
export 'src/docs/structure_hash.dart';
export 'src/docs/folder_graph.dart';
export 'src/docs/topological_sort.dart';
export 'src/docs/doc_manifest.dart';
export 'src/docs/link_transformer.dart';
export 'src/docs/context_extractor.dart';
export 'src/docs/context_builder.dart';
export 'src/docs/context_formatter.dart';
export 'src/docs/dirty_tracker.dart';
export 'src/docs/llm_interface.dart';