# LLM-Generated Documentation

## Overview

code_context enables automatic generation of human-readable documentation using LLMs, with SCIP-based dependency tracking for efficient incremental updates. This is similar to tools like DeepWiki or Code Wiki, but leverages our existing SCIP infrastructure for smarter change detection.

## Design Goals

1. **LLM-synthesized prose** - Not just symbol listings, but actual documentation
2. **Smart symbols** - References that link to code and other doc sections
3. **Bottom-up generation** - Folder → module → project hierarchy
4. **Incremental updates** - Only regenerate docs whose dependencies changed
5. **External package docs** - Generate and cache docs for all dependencies

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    LLM Documentation Pipeline                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────┐     ┌──────────────┐     ┌───────────────────┐   │
│  │  SCIP Index  │────▶│  Doc Context │────▶│  LLM Synthesis    │   │
│  │  + Analyzer  │     │  Builder     │     │                   │   │
│  └──────────────┘     └──────────────┘     └─────────┬─────────┘   │
│                                                       │             │
│                                                       ▼             │
│  ┌──────────────┐     ┌──────────────┐     ┌───────────────────┐   │
│  │  Dependency  │◀────│  Smart Token │◀────│  Generated Doc    │   │
│  │  Tracker     │     │  Linker      │     │  with References  │   │
│  └──────────────┘     └──────────────┘     └───────────────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Bottom-Up Generation

Documentation is generated hierarchically:

```
Project Root
├── docs/
│   ├── index.md                    # Synthesized from module docs
│   ├── modules/
│   │   ├── auth.md                 # Synthesized from folder docs
│   │   └── products.md
│   └── folders/
│       ├── lib/features/auth/      # Generated from code + comments
│       └── lib/features/products/
```

### Generation Flow

1. **Folder-level** (lowest): LLM reads source files, doc comments, and generates prose
2. **Module-level**: LLM reads folder-level docs, synthesizes higher-level overview
3. **Project-level**: LLM reads module-level docs, creates project overview

File-level documentation stays in the source files as doc comments (`///`), maintained by developers or AI coding assistants.

## Smart Symbols

Generated docs contain **smart symbols** - references to specific code elements:

```markdown
The [`AuthService`][auth-service] handles user authentication by delegating
to the [`AuthRepository`][auth-repo] for data persistence.

[auth-service]: scip-dart://lib/services/auth_service.dart/AuthService#
[auth-repo]: scip-dart://lib/repositories/auth_repository.dart/AuthRepository#
```

These symbols enable:
- **Navigation**: Click to jump to code or related docs
- **Change tracking**: When the referenced symbol changes, the doc section is marked dirty
- **Bidirectional linking**: Code knows which docs reference it

## Dependency Tracking

SCIP provides the dependency graph for efficient invalidation:

### What Triggers Regeneration?

| Scope | Regenerate When |
|-------|-----------------|
| Folder doc | Any file in folder changes, or any referenced symbol changes |
| Module doc | Any child folder doc changes |
| Project doc | Any module doc changes |

### How It Works

```
1. Each doc section tracks its dependencies:
   - Source files it was generated from
   - SCIP symbols it references (smart tokens)
   - Child docs it synthesizes from

2. On file change:
   - SCIP detects changed symbols via hash comparison
   - Mark dependent doc sections as dirty
   - Propagate dirty state up the hierarchy

3. On doc regeneration:
   - Only regenerate dirty sections
   - Re-link smart symbols to current code
   - Update dependency manifest
```

### Manifest Structure

```json
{
  "version": 1,
  "sections": {
    "modules/auth": {
      "generatedAt": "2025-01-12T10:00:00Z",
      "sourceFiles": ["lib/features/auth/*.dart"],
      "referencedSymbols": [
        "scip-dart://lib/services/auth_service.dart/AuthService#",
        "scip-dart://lib/repositories/auth_repository.dart/AuthRepository#"
      ],
      "childDocs": ["folders/lib/features/auth/login", "folders/lib/features/auth/signup"],
      "contentHash": "abc123..."
    }
  }
}
```

## Cache Structure

Docs are stored alongside SCIP indexes:

```
/path/to/package/.dart_context/
├── index.scip              # SCIP index
├── manifest.json           # Index manifest
└── docs/
    ├── manifest.json       # Doc dependency manifest
    ├── index.md            # Project-level doc
    ├── modules/
    │   ├── auth.md
    │   └── products.md
    └── folders/
        └── lib/
            └── features/
                └── auth/
                    └── README.md
```

### External Package Docs

```
~/.dart_context/
├── hosted/http-1.2.0/
│   ├── index.scip
│   └── docs/
│       ├── manifest.json
│       └── index.md        # LLM-generated overview of http package
└── flutter/3.32.0/material/
    ├── index.scip
    └── docs/
        └── index.md        # Generated once, cached forever per version
```

Benefits:
- Generate once per package version
- Shared across all projects using that version
- No LLM cost for unchanged dependencies

## LLM Context Building

When generating a doc section, we provide the LLM with:

### For Folder-Level Docs

```
1. Source files in the folder (filtered to relevant parts)
2. Doc comments (///) from those files
3. SCIP symbol information:
   - Public API surface
   - Type hierarchy
   - Call graph (what calls what)
4. Existing folder README if present (for context)
```

### For Module-Level Docs

```
1. All child folder docs
2. Module's public API surface (from SCIP)
3. Cross-folder dependencies (from call graph)
4. Existing module docs if present
```

### For Project-Level Docs

```
1. All module docs
2. Project structure overview
3. Entry points and navigation flow
4. README.md if present
```

## Incremental Update Example

```
Initial state:
  - All docs generated
  - Manifest tracks dependencies

Developer modifies: lib/features/auth/login_service.dart

Change detection:
  1. SCIP hash comparison detects file changed
  2. Find doc sections referencing symbols in that file:
     - folders/lib/features/auth/README.md (direct)
     - modules/auth.md (parent)
     - index.md (root)
  3. Mark these as dirty

Regeneration:
  1. Regenerate folders/lib/features/auth/README.md (reads new code)
  2. Regenerate modules/auth.md (reads updated folder doc)
  3. Regenerate index.md (reads updated module doc)
  4. Update manifest with new hashes

Result:
  - Only 3 LLM calls instead of full project regeneration
  - Smart symbols re-linked to current code
```

## Comparison with DeepWiki/Code Wiki

| Aspect | code_context | DeepWiki/Code Wiki |
|--------|--------------|-------------------|
| Index | SCIP (we control it) | Their own static analysis |
| Languages | Dart-focused (extensible) | Multi-language |
| Dependency tracking | SCIP symbols + call graph | File-level or custom |
| External packages | Cached per version | Single repo only? |
| Incremental updates | Symbol-level granularity | File-level? |
| Hosting | Self-hosted / local | Cloud service |
| Cost | Pay for LLM only | Subscription |

### Our Advantages

1. **SCIP integration**: We already have the index, just add doc layer
2. **Symbol-level tracking**: Finer granularity than file-level
3. **External package docs**: Generate once, cache forever
4. **Dart expertise**: Deep Flutter/Dart knowledge (navigation, widgets, etc.)
5. **Local-first**: No cloud dependency, run anywhere

## CLI Commands (Planned)

```bash
# Generate all docs (or update dirty ones)
code_context docs generate -p /path/to/project

# Force full regeneration
code_context docs generate -p /path/to/project --force

# Show dirty status (what needs regeneration)
code_context docs status -p /path/to/project

# Generate docs for external dependencies
code_context docs generate-deps -p /path/to/project

# View a doc section
code_context docs view auth

# List doc sections and their status
code_context docs list
```

## Implementation Status

- [ ] Doc context builder (extract relevant code for LLM)
- [ ] LLM synthesis pipeline (prompt engineering)
- [ ] Smart symbol extraction and linking
- [ ] Dependency manifest and tracking
- [ ] Dirty detection and incremental regeneration
- [ ] External package doc generation
- [ ] CLI commands

## Related

- [Architecture](architecture.md) - System design
- [Flutter Navigation](flutter-navigation.md) - Navigation flow detection
- [Cross-Package Queries](cross-package-queries.md) - External package indexing
