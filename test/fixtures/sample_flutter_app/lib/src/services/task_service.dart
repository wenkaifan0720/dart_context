import '../models/task.dart';

/// Service for managing tasks.
///
/// This is an in-memory implementation for demo purposes.
/// In a real app, this would persist to local storage or a backend.
class TaskService {
  final List<Task> _tasks = [];

  /// Returns all tasks.
  Future<List<Task>> getTasks() async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 100));
    return List.unmodifiable(_tasks);
  }

  /// Returns a task by ID.
  Future<Task?> getTask(String id) async {
    await Future.delayed(const Duration(milliseconds: 50));
    try {
      return _tasks.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Adds a new task.
  Future<void> addTask(Task task) async {
    await Future.delayed(const Duration(milliseconds: 50));
    _tasks.add(task.copyWith(createdAt: DateTime.now()));
  }

  /// Updates an existing task.
  Future<void> updateTask(Task task) async {
    await Future.delayed(const Duration(milliseconds: 50));
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      _tasks[index] = task;
    }
  }

  /// Toggles the completion status of a task.
  Future<void> toggleTask(String id) async {
    await Future.delayed(const Duration(milliseconds: 50));
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index != -1) {
      final task = _tasks[index];
      _tasks[index] = task.copyWith(isCompleted: !task.isCompleted);
    }
  }

  /// Deletes a task by ID.
  Future<void> deleteTask(String id) async {
    await Future.delayed(const Duration(milliseconds: 50));
    _tasks.removeWhere((t) => t.id == id);
  }

  /// Returns the count of completed tasks.
  int get completedCount => _tasks.where((t) => t.isCompleted).length;

  /// Returns the count of pending tasks.
  int get pendingCount => _tasks.where((t) => !t.isCompleted).length;

  /// Clears all completed tasks.
  Future<void> clearCompleted() async {
    await Future.delayed(const Duration(milliseconds: 50));
    _tasks.removeWhere((t) => t.isCompleted);
  }
}
