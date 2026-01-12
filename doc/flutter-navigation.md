# Flutter Navigation Detection

## Overview

code_context can detect and visualize navigation flows in Flutter applications. This is a Flutter-specific feature that uses AST parsing and SCIP data to build a navigation graph.

## Quick Start

```bash
# Generate navigation graph (JSON format)
code_context storyboard -p /path/to/flutter/project --format json

# Generate navigation graph (text format)
code_context storyboard -p /path/to/flutter/project --format text

# As part of generate-docs
code_context generate-docs -p /path/to/flutter/project
```

## Supported Navigation Patterns

### go_router (Full Support)

Detects routes via AST parsing:

```dart
// Route definitions
GoRoute(
  path: '/home',
  name: 'home',
  builder: (context, state) => HomePage(),
)

// Navigation calls
context.go('/home');
context.push('/project/$id');
context.goNamed('home');
context.pushNamed('settings');
context.push(Routes.newProject);  // Constant references
```

Also supports:
- `ShellRoute` and `StatefulShellRoute`
- `pageBuilder` with conditional children
- Route constants (`Routes.home`, `Routes.settings`)

### Other Routers (Regex-Based)

| Router | Detection |
|--------|-----------|
| Navigator | `Navigator.push`, `Navigator.pushNamed` |
| auto_route | `context.router.push`, `AutoRoute` annotations |
| GetX | `Get.to`, `Get.toNamed`, `Get.offNamed` |

## Page Detection

Only actual "pages" are included in the navigation graph:

1. **Naming convention**: Class ends with `Page`, `Screen`, or `View`
2. **Scaffold detection**: Class's `build()` method contains a `Scaffold` widget (via AST)

Non-page widgets that trigger navigation are captured in the trigger context instead.

## Trigger Context

Each navigation edge includes a detailed trigger chain:

```
DashboardPage → _buildProjectCard() → onTap: → context.push('/project/$id')
```

The chain is extracted using Dart Analyzer AST and includes:
- Class/method boundaries
- Widget instantiation context
- Callback parameters (`onTap:`, `onPressed:`)
- Control flow conditions (`if(isLoggedIn)`)

### How It Works

1. **SCIP provides widget class set**: Query type hierarchy for `StatelessWidget`, `StatefulWidget`, `State` implementations
2. **AST traversal**: Walk from file root to navigation call, recording containment chain
3. **Node classification**: Identify classes, methods, widgets, callbacks, control flow
4. **Chain formatting**: Produce human-readable `Page → method() → callback:` format

## Output Formats

### JSON (`--format json`)

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
      "trigger": "LoginPage → _handleLogin() → onPressed:",
      "routePath": "/home"
    }
  ],
  "entryPoint": "SplashPage"
}
```

### Text (`--format text`)

```
# Navigation Graph

Entry Point: SplashPage

## Pages
- SplashPage
- LoginPage  
- HomePage

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

## Implementation

### Key Components

| Component | Location | Description |
|-----------|----------|-------------|
| `FlutterNavigationDetector` | `dart_binding` | Main detection logic |
| `DartNavigationChainExtractor` | `dart_binding` | AST-based trigger extraction |
| `NavigationBinding` | `scip_server` | Language-agnostic interface |

### Detection Flow

```
1. Parse router files (AST) → Build route-to-screen map
2. Find page widgets (naming + Scaffold detection)
3. Scan all files for navigation calls
4. For each call: extract trigger chain via AST
5. Build graph with pages as nodes, navigations as edges
6. Detect entry point (SplashPage, HomePage, or first page)
```

## Limitations

- Regex-based detection for non-go_router may miss edge cases
- Dynamic route generation (programmatic routes) not fully supported
- Deep links defined outside Dart code not detected

## Related

- [Query DSL](query-dsl.md) - `storyboard` command
- [Architecture](architecture.md) - System design
