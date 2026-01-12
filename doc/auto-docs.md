# Auto-Generated Documentation

## Overview

code_context can automatically generate structured documentation for Dart/Flutter projects. The docs are derived from SCIP index data, extracting architecture patterns, navigation flows, and symbol classifications.

```
┌─────────────────────────────────────────────────────────────────┐
│                     Auto-Doc Generation                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐     ┌──────────────┐     ┌─────────────────┐ │
│  │  SCIP Index  │────▶│  Classifiers │────▶│  Markdown/JSON  │ │
│  │  + Analyzer  │     │              │     │  Documentation  │ │
│  └──────────────┘     └──────────────┘     └─────────────────┘ │
│                              │                                  │
│              ┌───────────────┼───────────────┐                  │
│              ▼               ▼               ▼                  │
│     ┌─────────────┐  ┌─────────────┐  ┌──────────────┐         │
│     │   Layer     │  │   Feature   │  │  Navigation  │         │
│     │ Classifier  │  │  Detector   │  │   Detector   │         │
│     └─────────────┘  └─────────────┘  └──────────────┘         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

### CLI Usage

```bash
# Generate all documentation views
code_context generate-docs -p /path/to/flutter/project

# Generate specific view
code_context generate-docs -p /path/to/project --mode layer
code_context generate-docs -p /path/to/project --mode feature
code_context generate-docs -p /path/to/project --mode module

# Specify output format
code_context generate-docs -p /path/to/project --format json
code_context generate-docs -p /path/to/project --format text
```

### Output Structure

Generated docs are stored in the project's `docs/` folder:

```
your_project/
└── docs/
    ├── index.md              # Overview with links to all docs
    ├── architecture-layer.md # By architectural layer (UI→Service→Data)
    ├── architecture-feature.md # By feature (auth, products, etc.)
    ├── architecture-module.md  # By package/module
    ├── navigation.json       # Navigation graph (JSON format)
    └── navigation.md         # Navigation graph (text format)
```

## Documentation Views

### 1. Layer View (`--mode layer`)

Organizes symbols by architectural layer:

- **UI** - Widgets, pages, screens
- **Service** - Business logic, use cases
- **Data** - Repositories, data sources
- **Model** - Domain models, entities
- **Utility** - Helpers, extensions, utils

Layer classification uses multiple signals:
- SCIP type hierarchy (extends Widget, implements Repository, etc.)
- SCIP call graph analysis (UI calls Service, Service calls Data)
- Naming conventions (*Widget, *Service, *Repository)
- File path patterns (lib/ui/, lib/services/, lib/data/)

### 2. Feature View (`--mode feature`)

Groups symbols by business feature:

- Detects features from directory structure (`features/auth/`, `modules/payment/`)
- Clusters related symbols using call graph analysis
- Shows each feature's layers (UI, Service, Data components)

Example output:
```
## auth
- LoginPage (UI)
- SignupPage (UI)
- AuthService (Service)
- AuthRepository (Data)
- User (Model)

## products
- ProductListPage (UI)
- ProductDetailPage (UI)
- ProductService (Service)
- ProductRepository (Data)
- Product (Model)
```

### 3. Module View (`--mode module`)

Shows package/module structure for monorepos:

```
## hologram_core
- DirectedGraph
- TreeNode
- ...

## hologram_server
- WidgetDefinitionVisitor
- AnalyzerService
- ...
```

## Navigation Detection

The navigation detector identifies screen-to-screen transitions:

### Supported Navigation Patterns

| Pattern | Detection Method |
|---------|------------------|
| go_router | AST parsing of `GoRoute`, `ShellRoute`, `StatefulShellRoute` |
| Named routes | `context.goNamed()`, `context.pushNamed()` |
| Path routes | `context.go('/path')`, `context.push('/path')` |
| Route constants | `context.push(Routes.newProject)` |
| Navigator.push | Regex pattern matching |
| auto_route | Regex pattern matching |
| GetX | Regex pattern matching |

### Page Detection

Only actual "pages" are included in the navigation graph:

1. **Naming convention**: Class ends with `Page`, `Screen`, or `View`
2. **Scaffold detection**: Class's `build()` method contains a `Scaffold` widget

Non-page widgets that trigger navigation are captured in the trigger context.

### Trigger Context

Each navigation edge includes a detailed trigger chain showing the path from page to navigation call:

```
DashboardPage → _buildProjectCard() → onTap: → context.push('/project/$id')
```

The chain includes:
- Class/method boundaries
- Widget instantiation context
- Callback parameters (`onTap:`, `onPressed:`)
- Control flow (`if(condition)`)

### Output Formats

**JSON** (`--format json`):
```json
{
  "nodes": [
    {"id": "LoginPage", "label": "LoginPage", "type": "page"},
    {"id": "HomePage", "label": "HomePage", "type": "page"}
  ],
  "edges": [
    {
      "from": "LoginPage",
      "to": "HomePage", 
      "trigger": "LoginPage → _handleLogin() → onPressed: → if(success)",
      "routePath": "/home"
    }
  ],
  "entryPoint": "SplashPage"
}
```

**Text** (`--format text`):
```
# Navigation Graph

Entry Point: SplashPage

## Pages
- SplashPage
- LoginPage
- HomePage
- SettingsPage

## Navigation Flows

SplashPage
  → LoginPage [/login]
    trigger: SplashPage → initState() → if(!isLoggedIn)
  → HomePage [/home]
    trigger: SplashPage → initState() → if(isLoggedIn)

LoginPage
  → HomePage [/home]
    trigger: LoginPage → _handleLogin() → onPressed:
```

## Cache Integration

Auto-generated docs can be stored alongside SCIP indexes:

```
/path/to/package/.dart_context/
├── index.scip          # SCIP index
├── manifest.json       # Cache validation
└── docs/               # Auto-generated docs
    ├── index.md
    ├── architecture-layer.md
    ├── architecture-feature.md
    ├── navigation.json
    └── lib/            # Per-folder docs (future)
        └── features/
            └── auth/
                └── README.md
```

### Incremental Documentation Updates

Docs follow the same invalidation logic as the SCIP index:

1. **File hash tracking**: Each doc knows which source files it depends on
2. **Dirty detection**: When source files change, dependent docs are marked dirty
3. **Bottom-up regeneration**: 
   - Folder-level docs regenerate first
   - Parent docs that depend on changed children regenerate next
   - Only affected docs are regenerated

### External Dependency Docs

Docs for external packages are cached globally:

```
~/.dart_context/
├── hosted/http-1.2.0/
│   ├── index.scip
│   └── docs/
│       ├── index.md
│       └── architecture-layer.md
└── flutter/3.32.0/material/
    ├── index.scip
    └── docs/
        └── index.md
```

Benefits:
- Generate once per package version, reuse forever
- No LLM costs for unchanged dependencies
- Cross-project documentation consistency

## Classification Details

### Layer Classification Signals

| Signal | Weight | Example |
|--------|--------|---------|
| SCIP type hierarchy | High | `extends StatelessWidget` → UI |
| SCIP call graph | High | Called by UI, calls Data → Service |
| Naming convention | Medium | `*Repository` → Data |
| File path | Medium | `lib/services/` → Service |
| Import analysis | Low | Imports `package:flutter/material.dart` → UI |

### Feature Detection Signals

| Signal | Description |
|--------|-------------|
| Directory structure | `features/auth/`, `modules/payment/` |
| Naming prefix | `Auth*`, `Product*` |
| Call graph clustering | Symbols that call each other frequently |

## Comparison with Manual Documentation

| Aspect | Auto-Generated | Manual |
|--------|---------------|--------|
| Maintenance | Automatic | Requires effort |
| Accuracy | Reflects actual code | Can become stale |
| Depth | Structure-focused | Can include rationale |
| Speed | Instant | Time-consuming |
| Use case | AI consumption, onboarding | Design decisions, ADRs |

**Recommendation**: Use auto-generated docs for structure/navigation, manual docs for architectural decisions and rationale.

## Future Enhancements

- [ ] Widget preview links (visual documentation)
- [ ] Per-folder README generation with LLM synthesis
- [ ] Smart token tracking for doc-to-code links
- [ ] Dependency-aware incremental doc regeneration
- [ ] External package doc generation and caching

## Related Documentation

- [Query DSL Reference](query-dsl.md) - Symbol queries
- [Architecture](architecture.md) - System design
- [Monorepo Support](monorepo.md) - Multi-package workspaces
