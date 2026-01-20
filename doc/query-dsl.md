# Query DSL Reference

code_context provides a human and LLM-friendly query DSL for navigating your codebase.

## Commands

| Query | Description | Example |
|-------|-------------|---------|
| `def <symbol>` | Find definition of a symbol | `def AuthRepository` |
| `refs <symbol>` | Find all references to a symbol | `refs login` |
| `sig <symbol>` | Get signature (without body) | `sig UserService` |
| `source <symbol>` | Get full source code | `source handleLogin` |
| `members <symbol>` | Get members of a class/mixin/extension | `members UserService` |
| `hierarchy <symbol>` | Full type hierarchy (supers + subs) | `hierarchy MyWidget` |
| `find <pattern>` | Search for symbols matching pattern | `find Auth*` |
| `calls <symbol>` | What does this symbol call? | `calls AuthService.login` |
| `callers <symbol>` | What calls this symbol? | `callers validateUser` |
| `imports <file>` | What does this file import? | `imports lib/auth.dart` |
| `exports <path>` | What does this file/directory export? | `exports lib/` |
| `symbols <file>` | List all symbols in a file | `symbols lib/auth.dart` |
| `files` | List all indexed files | `files` |
| `stats` | Get index statistics | `stats` |

## Pattern Syntax

| Pattern | Type | Description | Example |
|---------|------|-------------|---------|
| `Auth*` | Glob | Wildcard matching | `*` = any chars, `?` = one char |
| `/TODO\|FIXME/` | Regex | Regular expression (between slashes) | |
| `/error/i` | Regex | Case-insensitive regex (with `i` flag) | |
| `~authentcate` | Fuzzy | Typo-tolerant matching | Finds "authenticate" |
| `login` | Literal | Exact match | |

## Qualified Names

When multiple symbols share the same name, use qualified names to disambiguate:

```bash
# Multiple "login" methods exist
refs AuthService.login      # References to login in AuthService only
def UserRepository.login    # Definition of login in UserRepository

# Discover all matches first
find login
# Output:
# 1. login [method] in AuthService (lib/auth/service.dart)
# 2. login [method] in UserRepository (lib/data/repo.dart)
# 3. LoginPage [class] (lib/ui/login_page.dart)
```

## Filters (for `find`)

| Filter | Description | Example |
|--------|-------------|---------|
| `kind:<kind>` | Filter by symbol kind | `find * kind:class` |
| `in:<path>` | Filter by file path prefix | `find * in:lib/auth/` |
| `lang:<language>` | Filter by programming language | `find String lang:Dart` |

**Symbol kinds:** `class`, `method`, `function`, `field`, `enum`, `mixin`, `extension`, `getter`, `setter`, `constructor`

**Languages:** `Dart` (more coming as language bindings are added)

## Pipe Queries

Chain queries with `|` to process results:

```bash
find Auth* kind:class | members   # Get members of all Auth classes
find *Service | refs              # Find refs for all services
members MyClass | source          # Get source for all members
members AppSpacing | find padding* kind:field  # Filter to specific members
```

When `find` is used after a pipe, it filters the incoming symbols rather than searching globally.

## Examples

```bash
# Find all classes starting with "Auth"
find Auth* kind:class

# Find all methods in lib/auth/
find * kind:method in:lib/auth/

# Find definition with wildcard
def AuthRepo*

# Get hierarchy of a widget
hierarchy MyWidget

# Fuzzy matching (typo-tolerant)
find ~authentcate              # Finds "authenticate" despite typo
find ~respnse                  # Finds "response"

# Case-insensitive search
find /error/i                  # Matches "Error", "ERROR", "error"

# Call graph queries
calls AuthService.login        # What does login() call?
callers validateUser           # What calls validateUser()?

# Import/export analysis
imports lib/auth/service.dart  # What does this file import?
exports lib/auth/              # What does this directory export?

# File-scoped queries
symbols lib/auth/service.dart  # List all symbols in this file

# Disambiguation workflow
find handleSubmit              # See all matches with container context
refs FormWidget.handleSubmit   # Get refs for specific one
```
