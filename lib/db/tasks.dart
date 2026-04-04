import 'package:googleapis/tasks/v1.dart';

/// A service to interact with Google Tasks.
class TaskService {
  /// The Google Tasks API client.
  final TasksApi tasksApi;

  /// The ID of the task list to use (defaults to "@default").
  final String taskListId; // e.g., "@default"

  /// Creates a [TaskService] with the required [tasksApi] and optional
  /// [taskListId].
  TaskService(this.tasksApi, {this.taskListId = '@default'});

  /// Creates a new task in Google Tasks.
  Future<Task> createTask(
    String title,
    String description,
    DateTime? dueDate,
  ) async {
    final task = Task(
      title: title,
      notes: description,
      due: dueDate
          ?.toUtc()
          .toIso8601String(), // Google Tasks expects UTC ISO string
    );

    return await tasksApi.tasks.insert(task, taskListId);
  }

  /// Deletes a task from Google Tasks by its [taskId].
  Future<void> deleteTask(String taskId) async {
    await tasksApi.tasks.delete(taskListId, taskId);
  }

  /// Updates the status of a task in Google Tasks.
  Future<void> updateTaskStatus(String taskId, bool completed) async {
    final task = await tasksApi.tasks.get(taskListId, taskId);
    task.status = completed ? 'completed' : 'needsAction';
    if (completed) {
      task.completed = DateTime.now().toUtc().toIso8601String();
    } else {
      task.completed = null; // Clear if unchecking
    }

    await tasksApi.tasks.update(task, taskListId, taskId);
  }

  /// Retrieves all upcoming tasks that need action.
  Future<List<Task>> getUpcomingTasks() async {
    final response = await tasksApi.tasks.list(taskListId);
    final tasks = response.items;
    if (tasks == null) return [];

    return tasks.where((t) => t.status == 'needsAction').toList();
  }

  /// Checks if a task is completed in Google Tasks.
  Future<bool> isTaskCompleted(String taskId) async {
    final task = await tasksApi.tasks.get(taskListId, taskId);
    return task.status == 'completed';
  }
}
