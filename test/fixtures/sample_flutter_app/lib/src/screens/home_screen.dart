import 'package:flutter/material.dart';

import '../models/task.dart';
import '../services/task_service.dart';
import '../widgets/task_list_tile.dart';

/// The main home screen displaying a list of tasks.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TaskService _taskService = TaskService();
  List<Task> _tasks = [];

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    final tasks = await _taskService.getTasks();
    setState(() {
      _tasks = tasks;
    });
  }

  Future<void> _addTask() async {
    final title = await _showAddTaskDialog();
    if (title != null && title.isNotEmpty) {
      final task = Task(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
      );
      await _taskService.addTask(task);
      await _loadTasks();
    }
  }

  Future<void> _toggleTask(Task task) async {
    await _taskService.toggleTask(task.id);
    await _loadTasks();
  }

  Future<void> _deleteTask(Task task) async {
    await _taskService.deleteTask(task.id);
    await _loadTasks();
  }

  Future<String?> _showAddTaskDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Task'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter task title',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
      ),
      body: _tasks.isEmpty
          ? const Center(
              child: Text('No tasks yet. Add one!'),
            )
          : ListView.builder(
              itemCount: _tasks.length,
              itemBuilder: (context, index) {
                final task = _tasks[index];
                return TaskListTile(
                  task: task,
                  onToggle: () => _toggleTask(task),
                  onDelete: () => _deleteTask(task),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTask,
        child: const Icon(Icons.add),
      ),
    );
  }
}
