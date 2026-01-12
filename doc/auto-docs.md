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

### Dependency Context Strategy

When generating docs for folder A, we need context about its dependencies:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Context for Folder A                          │
├─────────────────────────────────────────────────────────────────┤
│  Full Context (current folder):                                  │
│    - All source files                                            │
│    - All doc comments                                            │
│    - Full SCIP symbol info                                       │
├─────────────────────────────────────────────────────────────────┤
│  Summary Context (dependencies):                                 │
│    - Doc summary (if already generated)                          │
│    - Public API signatures only                                  │
│    - Which specific symbols are used                             │
├─────────────────────────────────────────────────────────────────┤
│  Mention Only (transitive deps):                                 │
│    - Just names and one-line descriptions                        │
└─────────────────────────────────────────────────────────────────┘
```

**Why this layering?**

1. **Token efficiency**: Full source for deps would explode context
2. **Bottom-up generation**: Dependency docs are generated first, so we can include their summaries
3. **SCIP provides the graph**: We know exactly which symbols are called
4. **Avoid circular issues**: We only include *outgoing* dependencies, not the full transitive closure

**What about dependents (who calls this folder)?**

Include a brief "dependents" section so the LLM understands how this code is used:
- Helps generate better "Usage" sections in docs
- Provides context for what's important to document

### Folder-Level Docs (Input)

The lowest level - generated directly from source code:

```yaml
# Context sent to LLM for: lib/features/auth/

metadata:
  path: lib/features/auth/
  purpose_hint: "auth feature (from path)"
  
files:
  - name: auth_service.dart
    doc_comments: |
      /// Handles user authentication and session management.
      /// 
      /// Uses [AuthRepository] for persistence and [TokenManager] for JWT handling.
    public_api:
      - "class AuthService"
      - "  Future<User> login(String email, String password)"
      - "  Future<void> logout()"
      - "  Stream<AuthState> get authStateChanges"
    
  - name: auth_repository.dart
    doc_comments: |
      /// Data layer for authentication.
    public_api:
      - "class AuthRepository"
      - "  Future<UserCredential> signIn(String email, String password)"

symbols:  # From SCIP
  definitions:
    - id: "scip://lib/features/auth/auth_service.dart/AuthService#"
      name: AuthService
      kind: class
      
  relationships:
    - AuthService calls AuthRepository.signIn
    - AuthService calls TokenManager.store
    - LoginPage calls AuthService.login
    
  imports:
    - package:firebase_auth/firebase_auth.dart
    - ../core/token_manager.dart

# Dependencies: folders/files this folder calls into
dependencies:
  internal:
    - path: lib/core/token_manager.dart
      # If doc already generated (bottom-up), include the doc summary
      doc_summary: |
        TokenManager handles secure storage and retrieval of JWT tokens.
        Key methods: store(), retrieve(), clear()
      # Always include the API signature from SCIP
      public_api:
        - "class TokenManager"
        - "  Future<void> store(String token)"
        - "  Future<String?> retrieve()"
        - "  Future<void> clear()"
      # Which specific symbols are called by current folder
      used_symbols:
        - TokenManager.store
        - TokenManager.retrieve
        
    - path: lib/data/user_dao.dart
      doc_summary: "Persists user data to local database."
      public_api:
        - "class UserDao"
        - "  Future<void> saveUser(User user)"
      used_symbols:
        - UserDao.saveUser
        
  external:  # From pub packages
    - package: firebase_auth
      version: 4.6.0
      # Include cached doc if available
      doc_summary: "Firebase Authentication SDK for Flutter."
      # Which symbols are used
      used_symbols:
        - FirebaseAuth.instance
        - UserCredential
        
# Dependents: who calls into this folder (for context on how it's used)
dependents:
  - path: lib/ui/login_page.dart
    uses:
      - AuthService.login
      - AuthService.authStateChanges
  - path: lib/features/profile/profile_service.dart
    uses:
      - AuthService.currentUser

existing_readme: |
  # Auth Feature
  (existing content if any - preserve user additions)
```

### Module-Level Docs (Input)

Synthesized from child folder docs:

```yaml
# Context sent to LLM for: auth module

metadata:
  name: auth
  folders: [lib/features/auth/, lib/services/auth/]

child_docs:
  - path: lib/features/auth/
    content: |
      ## Auth Feature
      The `AuthService` handles user authentication...
      
  - path: lib/services/auth/
    content: |
      ## Auth Services
      Token management and session handling...

cross_folder_dependencies:
  - auth/AuthService -> core/TokenManager
  - auth/AuthRepository -> data/UserDao

public_api_surface:
  - AuthService (main entry point)
  - AuthState (state enum)
  - User (model)
```

### Project-Level Docs (Input)

Synthesized from module docs:

```yaml
# Context sent to LLM for: project root

metadata:
  name: my_flutter_app
  description: "From pubspec.yaml"
  
module_docs:
  - name: auth
    summary: "User authentication and session management"
  - name: products  
    summary: "Product catalog and inventory"
  - name: core
    summary: "Shared utilities and base classes"

entry_points:
  - main.dart -> MyApp -> MaterialApp
  
navigation_summary:  # From flutter-navigation
  entry: SplashPage
  main_flows:
    - SplashPage -> LoginPage -> HomePage
    - HomePage -> ProductListPage -> ProductDetailPage

existing_readme: |
  # My Flutter App
  (preserve existing content)
```

## LLM Output Structure

### Folder-Level Doc Output

```markdown
# Auth Feature

## Overview

The auth feature handles user authentication, session management, and 
credential persistence. It integrates with Firebase Auth for identity 
and uses local token storage for offline capability.

## Key Components

- [`AuthService`][auth-service] - Main authentication orchestrator
  - `login(email, password)` - Authenticate user credentials
  - `logout()` - Clear session and tokens
  - `authStateChanges` - Stream of authentication state updates

- [`AuthRepository`][auth-repo] - Data layer for auth operations
  - Wraps Firebase Auth SDK
  - Handles credential caching

## How It Works

1. User enters credentials on [`LoginPage`][login-page]
2. [`AuthService.login()`][auth-login] validates and calls repository
3. On success, tokens stored via [`TokenManager`][token-mgr]
4. [`authStateChanges`][auth-stream] emits new state, triggering navigation

## Dependencies

- **Internal**: [`TokenManager`][token-mgr] (core), [`UserDao`][user-dao] (data)
- **External**: `firebase_auth`, `shared_preferences`

## Related

- [Login Page](../ui/login_page.md) - UI for this feature
- [Token Manager](../core/token_manager.md) - Token storage

<!-- Smart Symbol Definitions -->
[auth-service]: scip://lib/features/auth/auth_service.dart/AuthService#
[auth-repo]: scip://lib/features/auth/auth_repository.dart/AuthRepository#
[auth-login]: scip://lib/features/auth/auth_service.dart/AuthService#login().
[login-page]: scip://lib/ui/login_page.dart/LoginPage#
[token-mgr]: scip://lib/core/token_manager.dart/TokenManager#
[auth-stream]: scip://lib/features/auth/auth_service.dart/AuthService#authStateChanges.
[user-dao]: scip://lib/data/user_dao.dart/UserDao#
```

### Module-Level Doc Output

```markdown
# Auth Module

## Overview

Authentication and authorization for the application. Manages user 
identity, sessions, and access control.

## Components

| Folder | Purpose |
|--------|---------|
| [features/auth/](./folders/lib/features/auth/) | Core auth logic |
| [services/auth/](./folders/lib/services/auth/) | Token & session mgmt |
| [ui/auth/](./folders/lib/ui/auth/) | Login, signup screens |

## Public API

The module exposes these key symbols:

- [`AuthService`][auth-service] - Primary interface for auth operations
- [`AuthState`][auth-state] - Enum: `authenticated`, `unauthenticated`, `loading`
- [`User`][user] - Authenticated user model

## Data Flow

```
LoginPage (UI)
    ↓ calls
AuthService (Service)
    ↓ calls
AuthRepository (Data)
    ↓ uses
Firebase Auth (External)
```

## Integration Points

- **Called by**: Navigation guards, profile features
- **Calls**: Core (TokenManager), Data (UserDao)

[auth-service]: scip://lib/features/auth/auth_service.dart/AuthService#
[auth-state]: scip://lib/features/auth/auth_state.dart/AuthState#
[user]: scip://lib/models/user.dart/User#
```

### Project-Level Doc Output

```markdown
# My Flutter App

## Overview

E-commerce application with user authentication, product catalog, 
and order management.

## Modules

| Module | Description | Entry Point |
|--------|-------------|-------------|
| [Auth](./modules/auth.md) | User authentication | `AuthService` |
| [Products](./modules/products.md) | Product catalog | `ProductService` |
| [Orders](./modules/orders.md) | Order management | `OrderService` |
| [Core](./modules/core.md) | Shared utilities | - |

## Architecture

```
┌─────────────────────────────────────────┐
│                   UI                     │
│  LoginPage, HomePage, ProductListPage   │
├─────────────────────────────────────────┤
│                Services                  │
│  AuthService, ProductService, OrderSvc  │
├─────────────────────────────────────────┤
│              Repositories               │
│  AuthRepo, ProductRepo, OrderRepo       │
├─────────────────────────────────────────┤
│                 Data                     │
│  Firebase, Local DB, API Client         │
└─────────────────────────────────────────┘
```

## User Flows

### Authentication
[`SplashPage`][splash] → [`LoginPage`][login] → [`HomePage`][home]

### Shopping  
[`HomePage`][home] → [`ProductListPage`][products] → [`ProductDetailPage`][detail] → [`CartPage`][cart]

## Getting Started

See [Getting Started Guide](./getting-started.md) for setup instructions.

[splash]: scip://lib/ui/splash_page.dart/SplashPage#
[login]: scip://lib/ui/login_page.dart/LoginPage#
[home]: scip://lib/ui/home_page.dart/HomePage#
[products]: scip://lib/ui/product_list_page.dart/ProductListPage#
[detail]: scip://lib/ui/product_detail_page.dart/ProductDetailPage#
[cart]: scip://lib/ui/cart_page.dart/CartPage#
```

## Smart Symbol Format

Smart symbols use a `scip://` URI scheme:

```
scip://<relative-path>/<SymbolName>#[member]

Examples:
- scip://lib/auth/service.dart/AuthService#
- scip://lib/auth/service.dart/AuthService#login().
- scip://lib/auth/service.dart/AuthService#authState.
```

These can be resolved to:
1. **Source code location** - Jump to definition
2. **Related doc section** - If that symbol has its own doc
3. **Hover info** - Show signature and doc comment

## Prompt Template (Example)

```
You are generating documentation for a Dart/Flutter codebase folder.

## Context
{folder_context_yaml}

## Instructions
1. Write clear, concise documentation for developers
2. Reference symbols using [Name][id] markdown link syntax
3. Include a "Smart Symbol Definitions" section at the end with scip:// URIs
4. Preserve any existing README content, integrating new information
5. Focus on HOW things work, not just WHAT exists
6. Mention dependencies and integration points

## Output Format
Use the folder-level doc structure shown above.
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

## Design Decisions

### 1. Generation Order (Topological Sort)

**Problem**: Bottom-up requires generating dependencies first. What if there are cycles?

**Decision**: 
- Use SCIP call graph to build dependency DAG at folder level
- If cycles exist (A ↔ B), generate together in same batch with mutual context
- Topological sort determines order; parallel generation for independent folders

### 2. Folder-Level Only

Docs are generated at folder level only. File-level documentation stays in source files as `///` comments, maintained by developers or AI coding assistants.

**Rationale**:
- Keeps docs close to code for file-level details
- Folder docs provide the "big picture" that's missing from source
- Simpler system with clear separation of concerns

### 3. Fully AI-Generated (No Human Edits)

Docs in `.dart_context/docs/` are fully AI-generated and can be regenerated at any time.

**Rationale**:
- Stored in `.dart_context/` (not `docs/`) signals "auto-generated"
- No merge conflicts or preservation logic needed
- Users who want custom docs can maintain them separately in `docs/`
- Simpler implementation

### 4. External Package Docs

For now, use existing documentation from pub.dev / package READMEs.

**Future**: May generate docs for poorly-documented packages using SCIP index.

### 5. Agentic Generation

Instead of a fixed pipeline, use an **agent-based approach**:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Doc Generation Agent                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Agent receives:                                                 │
│    - Target folder path                                          │
│    - Initial context (SCIP symbols, file list)                   │
│                                                                  │
│  Agent has tools:                                                │
│    - read_file(path) - Read any file in the project             │
│    - query_scip(query) - Query the SCIP index                   │
│    - read_doc(path) - Read already-generated folder docs        │
│    - read_pubspec() - Get project metadata                      │
│    - list_files(folder) - Explore folder structure              │
│                                                                  │
│  Agent decides:                                                  │
│    - What files to read in detail                                │
│    - What dependencies to explore                                │
│    - What SCIP queries to make                                   │
│    - When it has enough context to generate                      │
│                                                                  │
│  Agent outputs:                                                  │
│    - Markdown doc with smart symbols                             │
│    - List of dependencies (for manifest)                         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Benefits**:
- Agent explores non-Dart files (YAML, JSON) as needed
- Handles large folders by selectively reading important files
- More flexible than fixed context building
- Can ask clarifying questions or make multiple passes

### 6. Model Selection by Scope

Different models for different doc levels:

| Scope | Model | Rationale |
|-------|-------|-----------|
| Folder docs | Cheaper (e.g., GPT-4o-mini, Claude Haiku) | Many folders, simpler context |
| Module docs | Mid-tier (e.g., GPT-4o, Claude Sonnet) | Synthesis from folder docs |
| Project docs | Premium (e.g., GPT-4, Claude Opus) | High-level, most visible |

Configurable via CLI: `--folder-model gpt-4o-mini --project-model gpt-4o`

### 7. Circular Dependencies

- Detect cycles during topological sort
- For cycles: Generate both folders in same agent session with mutual context
- Agent can query both folders' SCIP data before generating either doc

### 8. Primary Use Case: Agent Consumption

These docs are primarily for **AI agents** to quickly understand the codebase:

- Agent receives user question about the code
- Agent queries doc index to find relevant folder/module docs
- Agent reads docs (faster than reading all source files)
- Agent can follow smart symbols to dive into code if needed

Secondary use case: Developer onboarding and reference.

## Deferred (Future Consideration)

- Quality signals and validation
- CI/CD integration  
- Prompt customization / config files
- Human edit preservation (if needed)

## Known Limitations

1. **No runtime information**: Docs are static analysis only
2. **Complex generics**: May not fully explain generic type relationships
3. **Dynamic code**: Reflection, code generation not well documented
4. **Cross-repo**: Currently single-repo focused (monorepo OK)

## Implementation Status

- [ ] Doc context builder (extract relevant code for LLM)
- [ ] LLM synthesis pipeline (prompt engineering)
- [ ] Smart symbol extraction and linking
- [ ] Dependency manifest and tracking
- [ ] Dirty detection and incremental regeneration
- [ ] External package doc generation
- [ ] Human edit preservation (markers)
- [ ] Quality signals and validation
- [ ] Cost estimation and dry-run mode
- [ ] CLI commands
- [ ] Config file support

## Related

- [Architecture](architecture.md) - System design
- [Flutter Navigation](flutter-navigation.md) - Navigation flow detection
- [Cross-Package Queries](cross-package-queries.md) - External package indexing
