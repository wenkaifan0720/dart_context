import 'package:flutter/material.dart';

import '../models/task.dart';

/// A list tile widget for displaying a task.
class TaskListTile extends StatelessWidget {
  /// Creates a task list tile.
  const TaskListTile({
    super.key,
    required this.task,
    this.onToggle,
    this.onDelete,
    this.onTap,
  });

  /// The task to display.
  final Task task;

  /// Called when the checkbox is toggled.
  final VoidCallback? onToggle;

  /// Called when the delete button is pressed.
  final VoidCallback? onDelete;

  /// Called when the tile is tapped.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete?.call(),
      background: Container(
        color: theme.colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: Icon(
          Icons.delete,
          color: theme.colorScheme.onError,
        ),
      ),
      child: ListTile(
        leading: Checkbox(
          value: task.isCompleted,
          onChanged: (_) => onToggle?.call(),
        ),
        title: Text(
          task.title,
          style: task.isCompleted
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.outline,
                )
              : null,
        ),
        subtitle: task.description != null ? Text(task.description!) : null,
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: onDelete,
        ),
        onTap: onTap,
      ),
    );
  }
}
