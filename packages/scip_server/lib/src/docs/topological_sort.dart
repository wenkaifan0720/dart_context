import 'folder_graph.dart';

/// Topological sort with Strongly Connected Component (SCC) detection.
///
/// Uses Tarjan's algorithm to find cycles (SCCs) and then performs
/// topological sort on the condensation graph (DAG of SCCs).
///
/// This is used to determine the order of documentation generation:
/// - Folders with no dependencies are generated first
/// - Folders in cycles (SCCs) are generated together
/// - Dependent folders are generated after their dependencies
class TopologicalSort {
  /// Sort folders in generation order.
  ///
  /// Returns a list of "generations", where each generation is a list of
  /// folders that can be generated in parallel (or together if they form a cycle).
  ///
  /// - Single-element lists: independent folder
  /// - Multi-element lists: folders in a cycle (must be generated together)
  static List<List<String>> sort(FolderDependencyGraph graph) {
    final sccs = findSCCs(graph.internalDependencyGraph);

    // Build a mapping from folder to its SCC index
    final folderToScc = <String, int>{};
    for (var i = 0; i < sccs.length; i++) {
      for (final folder in sccs[i]) {
        folderToScc[folder] = i;
      }
    }

    // Build condensation graph (DAG of SCCs)
    final sccDeps = <int, Set<int>>{};
    for (var i = 0; i < sccs.length; i++) {
      sccDeps[i] = {};
    }

    for (final entry in graph.internalDependencyGraph.entries) {
      final fromScc = folderToScc[entry.key];
      if (fromScc == null) continue;

      for (final dep in entry.value) {
        final toScc = folderToScc[dep];
        if (toScc != null && toScc != fromScc) {
          sccDeps[fromScc]!.add(toScc);
        }
      }
    }

    // Topological sort of SCCs using Kahn's algorithm
    final inDegree = <int, int>{};
    for (var i = 0; i < sccs.length; i++) {
      inDegree[i] = 0;
    }
    for (final deps in sccDeps.values) {
      for (final dep in deps) {
        inDegree[dep] = (inDegree[dep] ?? 0) + 1;
      }
    }

    final result = <List<String>>[];
    final queue = <int>[];

    // Start with SCCs that have no dependencies
    for (var i = 0; i < sccs.length; i++) {
      if (inDegree[i] == 0) {
        queue.add(i);
      }
    }

    while (queue.isNotEmpty) {
      final sccIndex = queue.removeAt(0);
      result.add(sccs[sccIndex].toList()..sort());

      for (final depScc in sccDeps[sccIndex]!) {
        inDegree[depScc] = inDegree[depScc]! - 1;
        if (inDegree[depScc] == 0) {
          queue.add(depScc);
        }
      }
    }

    // Reverse because we built dependencies backwards
    // (we want dependencies before dependents)
    return result.reversed.toList();
  }

  /// Find Strongly Connected Components using Tarjan's algorithm.
  ///
  /// Returns a list of SCCs, where each SCC is a set of folders.
  /// Single-folder SCCs indicate no cycle; multi-folder SCCs indicate cycles.
  static List<Set<String>> findSCCs(Map<String, Set<String>> graph) {
    final index = <String, int>{};
    final lowLink = <String, int>{};
    final onStack = <String, bool>{};
    final stack = <String>[];
    final sccs = <Set<String>>[];
    var currentIndex = 0;

    void strongConnect(String node) {
      index[node] = currentIndex;
      lowLink[node] = currentIndex;
      currentIndex++;
      stack.add(node);
      onStack[node] = true;

      final neighbors = graph[node] ?? {};
      for (final neighbor in neighbors) {
        if (!index.containsKey(neighbor)) {
          // Neighbor not yet visited
          strongConnect(neighbor);
          lowLink[node] = _min(lowLink[node]!, lowLink[neighbor]!);
        } else if (onStack[neighbor] == true) {
          // Neighbor is on stack, so it's in the current SCC
          lowLink[node] = _min(lowLink[node]!, index[neighbor]!);
        }
      }

      // If node is a root of an SCC
      if (lowLink[node] == index[node]) {
        final scc = <String>{};
        String w;
        do {
          w = stack.removeLast();
          onStack[w] = false;
          scc.add(w);
        } while (w != node);
        sccs.add(scc);
      }
    }

    // Process all nodes (including disconnected ones)
    for (final node in graph.keys) {
      if (!index.containsKey(node)) {
        strongConnect(node);
      }
    }

    return sccs;
  }

  static int _min(int a, int b) => a < b ? a : b;

  /// Check if the graph has any cycles.
  static bool hasCycles(Map<String, Set<String>> graph) {
    final sccs = findSCCs(graph);
    return sccs.any((scc) => scc.length > 1);
  }

  /// Get all cycles in the graph.
  ///
  /// Returns only the SCCs with more than one node (actual cycles).
  static List<Set<String>> getCycles(Map<String, Set<String>> graph) {
    final sccs = findSCCs(graph);
    return sccs.where((scc) => scc.length > 1).toList();
  }
}
