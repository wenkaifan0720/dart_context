/// A task model representing a to-do item.
class Task {
  /// Creates a new task.
  const Task({
    required this.id,
    required this.title,
    this.description,
    this.isCompleted = false,
    this.createdAt,
  });

  /// Unique identifier for the task.
  final String id;

  /// The task title.
  final String title;

  /// Optional description.
  final String? description;

  /// Whether the task is completed.
  final bool isCompleted;

  /// When the task was created.
  final DateTime? createdAt;

  /// Creates a copy with updated fields.
  Task copyWith({
    String? id,
    String? title,
    String? description,
    bool? isCompleted,
    DateTime? createdAt,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Converts the task to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'isCompleted': isCompleted,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  /// Creates a task from a JSON map.
  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      isCompleted: json['isCompleted'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }

  @override
  String toString() => 'Task(id: $id, title: $title, isCompleted: $isCompleted)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Task &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
