class Task{
  final int id;
  final String name;
  final String? description;
  final bool completed;

  Task({
    required this.id,
    required this.name,
    this.description,
    this.completed = false,
  });

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'completed': completed,
    };
  }
}