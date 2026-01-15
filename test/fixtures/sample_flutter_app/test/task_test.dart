import 'package:flutter_test/flutter_test.dart';
import 'package:sample_flutter_app/src/models/task.dart';
import 'package:sample_flutter_app/src/services/task_service.dart';

void main() {
  group('Task', () {
    test('creates a task with required fields', () {
      const task = Task(id: '1', title: 'Test Task');

      expect(task.id, '1');
      expect(task.title, 'Test Task');
      expect(task.isCompleted, false);
      expect(task.description, isNull);
    });

    test('copyWith creates a new task with updated fields', () {
      const task = Task(id: '1', title: 'Original');
      final updated = task.copyWith(title: 'Updated', isCompleted: true);

      expect(updated.id, '1');
      expect(updated.title, 'Updated');
      expect(updated.isCompleted, true);
    });

    test('toJson and fromJson round-trip', () {
      final task = Task(
        id: '1',
        title: 'Test',
        description: 'Description',
        isCompleted: true,
        createdAt: DateTime(2024, 1, 15),
      );

      final json = task.toJson();
      final restored = Task.fromJson(json);

      expect(restored.id, task.id);
      expect(restored.title, task.title);
      expect(restored.description, task.description);
      expect(restored.isCompleted, task.isCompleted);
    });
  });

  group('TaskService', () {
    late TaskService service;

    setUp(() {
      service = TaskService();
    });

    test('starts empty', () async {
      final tasks = await service.getTasks();
      expect(tasks, isEmpty);
    });

    test('adds and retrieves tasks', () async {
      const task = Task(id: '1', title: 'New Task');
      await service.addTask(task);

      final tasks = await service.getTasks();
      expect(tasks.length, 1);
      expect(tasks.first.title, 'New Task');
    });

    test('toggles task completion', () async {
      const task = Task(id: '1', title: 'Task');
      await service.addTask(task);

      await service.toggleTask('1');
      var tasks = await service.getTasks();
      expect(tasks.first.isCompleted, true);

      await service.toggleTask('1');
      tasks = await service.getTasks();
      expect(tasks.first.isCompleted, false);
    });

    test('deletes tasks', () async {
      const task = Task(id: '1', title: 'Task');
      await service.addTask(task);

      await service.deleteTask('1');
      final tasks = await service.getTasks();
      expect(tasks, isEmpty);
    });
  });
}
