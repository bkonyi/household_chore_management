import 'dart:convert';
import 'package:genkit/genkit.dart';
import 'package:genkit_google_genai/genkit_google_genai.dart';
import 'package:googleapis/tasks/v1.dart' as tasks;
import '../db/sheet.dart';
import '../db/tasks.dart';

/// A service that interacts with GenKit and Gemini for natural language
/// processing and generation of chore-related responses.
class GenKitService {
  /// The Genkit instance used for AI operations.
  late final Genkit ai;

  /// The service used to interact with the Google Sheet database.
  final ChoreDatabase sheetService;

  /// The service used to interact with Google Tasks (optional).
  final TaskService? taskService;

  /// The Gemini API key.
  final String apiKey;

  /// Creates a [GenKitService] with the required [sheetService] and [apiKey].
  GenKitService(this.sheetService, this.apiKey, {this.taskService}) {
    ai = Genkit(plugins: [googleAI(apiKey: apiKey)]);
  }

  /// Generates a friendly reminder message for the given [upcomingChores].
  Future<String> generateFriendlyReminder(
    List<ChoreTask> upcomingChores,
  ) async {
    final choresText = upcomingChores
        .map((c) => '- ${c.taskName} (Due: ${_formatDate(c.dueDate)})')
        .join('\n');

    final prompt =
        '''
You are a friendly, professional household chore assistant. 
The current date and time is ${DateTime.now().toUtc().toIso8601String()}. Please use this context when interpreting relative dates like 'tomorrow', 'next monday', or calculating due dates!

Please remind the user about the following upcoming chores. 
Be encouraging and help them keep their workload reasonable.

Upcoming Chores:
$choresText
''';

    try {
      final response = await ai.generate<Object?, String>(
        model: googleAI.gemini(
          'gemini-2.5-flash',
        ), // Use a standard Gemini model available in the plugin
        prompt: prompt,
      );

      return response.text;
    } catch (e) {
      return 'I encountered an error communicating with Gemini '
          '(likelihood quota exceeded): $e';
    }
  }

  /// Generates friendly suggestions from [matchingChores] based on the user's
  /// [energy] level, available [time], and current [weather].
  Future<String> generateFriendlySuggestions(
    List<ChoreTask> matchingChores,
    int energy,
    int time, {
    String? weather,
  }) async {
    final choresText = matchingChores
        .map(
          (c) =>
              '- ${c.taskName} (Difficulty: ${c.difficulty}, '
              'Priority: ${c.priority})',
        )
        .join('\n');

    final prompt =
        '''
You are a friendly, professional household chore assistant.
The current date and time is ${DateTime.now().toUtc().toIso8601String()}.The user has an energy level of $energy/5 and $time minutes available for chores.
Current Weather: ${weather ?? 'Not specified (assume fair weather)'}.

If the weather is Rainy, Overcast, or snowy, please avoid suggesting outdoor tasks like mowing the lawn, washing the car, or painting the fence (unless they are urgent interior chores).
If the weather is Sunny, Clear, or beautiful, please prioritize outdoor tasks!
Use your natural understanding of words to infer if a task is "Outdoors" or "Indoors" based on its name and description.

I have found the following matching chores from their list.
Please suggest which ones to do and encourage them.
If there are many chores, suggest a subset to keep the workload reasonable.

Matching Chores:
$choresText
''';

    try {
      final response = await ai.generate<Object?, String>(
        model: googleAI.gemini('gemini-2.5-flash'),
        prompt: prompt,
      );

      return response.text;
    } catch (e) {
      return 'I encountered an error communicating with Gemini '
          '(likelihood quota exceeded): $e';
    }
  }

  /// Processes a chat [message] from the user, performing actions or replying
  /// naturally.
  Future<String> processChat(String message) async {
    await syncWithGoogleTasks();
    final chores = await sheetService.getChores();
    final choresList = chores
        .map((c) => '- "${c.taskName}" (Difficulty: ${c.difficulty}, '
            'Priority: ${c.priority}, Due: ${_formatDate(c.dueDate)})')
        .join('\n');

    final prompt =
        '''
You are a friendly, professional household chore assistant. 
The current date and time is ${DateTime.now().toUtc().toIso8601String()}. Please use this context when interpreting relative dates like 'tomorrow', 'next monday', or calculating due dates!
If the user does NOT explicitly specify a due date (either by exact date or relative term like 'next week', 'by Friday', 'tomorrow'), do NOT output a dueDate! Leave it as null or omit it from the JSON. Do NOT guess or estimate a due date based on the task type or description!
If the user mentions an event date or other important context (e.g., 'wedding on June 5th') that is distinct from the due date, please extract that context and include it in the "description" field!

Available Active Chores:
$choresList

The user will chat with you naturally. 
If the user wants to perform actions, you can respond with a JSON array containing action objects (even if there is only one action). If there are multiple actions, include them all in the array!

Action Object Schemas:

Add a chore:
{
  "action": "addChore",
  "taskName": "Clean the kitchen",
  "description": "Wash dishes, wipe counters",
  "difficulty": 3,
  "priority": "medium",
  "dueDate": "2026-04-01",
  "recurrenceRule": "Every week"
}

Remove a chore:
{
  "action": "removeChore",
  "taskName": "Fold laundry"
}

Mark a chore as completed:
{
  "action": "completeChore",
  "taskName": "Fold laundry"
}

Update a chore due date:
{
  "action": "updateChoreDueDate",
  "taskName": "Clean the kitchen",
  "dueDate": "2026-05-01"
}

If the user is just chatting or you are just replying without performing an action, respond with a friendly natural language response. Do NOT use JSON if you are just chatting.

Conversation:
$message
''';

    String text;
    try {
      final responseText = await callGemini(prompt);
      text = responseText.trim();

      // Strip markdown fences if present
      if (text.startsWith('```json')) {
        text = text.substring(7);
      } else if (text.startsWith('```')) {
        text = text.substring(3);
      }
      if (text.endsWith('```')) {
        text = text.substring(0, text.length - 3);
      }
      text = text.trim();
    } catch (e) {
      return 'I encountered an error communicating with Gemini '
          '(likelihood quota exceeded): $e';
    }
    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        final actions = text.startsWith('[')
            ? jsonDecode(text) as List<Object?>
            : [jsonDecode(text)];

        final removeCount = actions
            .where(
              (a) => a is Map<String, Object?> && a['action'] == 'removeChore',
            )
            .length;
        final isConfirmed = message.toLowerCase().contains('confirm');

        if (removeCount > 1 && !isConfirmed) {
          return '⚠️ I detected a request to remove multiple tasks '
              '($removeCount). '
              'Are you sure you want to proceed? '
              'Please type "yes confirm remove all tasks" to execute.';
        }

        final replies = <String>[];

        for (final actionData in actions) {
          if (actionData is! Map<String, Object?>) continue;

          final action = actionData['action'] as String?;

          if (action == 'addChore') {
            await _handleAddChore(actionData, replies);
          } else if (action == 'removeChore') {
            await _handleRemoveChore(actionData, replies);
          } else if (action == 'completeChore') {
            await _handleCompleteChore(actionData, replies);
          } else if (action == 'updateChoreDueDate') {
            await _handleUpdateChoreDueDate(actionData, replies);
          }
        }

        if (replies.isNotEmpty) {
          return replies.join('\n\n');
        }
      } catch (e) {
        // Fallback if parsing fails
        return 'I understood you want to perform action(s), '
            'but I had trouble parsing the details: $e';
      }
    }

    return text;
  }

  Future<void> _handleAddChore(
      Map<String, Object?> actionData, List<String> replies) async {
    final taskName = actionData['taskName'] as String?;
    if (taskName != null && taskName.isNotEmpty) {
      final description = actionData['description'] as String? ?? '';
      final difficulty = actionData['difficulty'] ?? 1;
      final priority = actionData['priority'] as String? ?? 'medium';
      final dueDateStr = actionData['dueDate'] as String?;
      final recurrenceRule = actionData['recurrenceRule'] as String?;

      DateTime? dueDate;
      if (dueDateStr != null && dueDateStr.isNotEmpty) {
        try {
          dueDate = DateTime.parse(dueDateStr).toUtc();
        } catch (e) {
          dueDate = null; // Do not default to today on parse error
        }
      } else {
        dueDate = null;
      }

      if (dueDate != null && dueDate.isBefore(DateTime.now().toUtc())) {
        replies
            .add('I cannot add tasks in the past. Please use a future date.');
        return;
      }

      if (dueDate == null &&
          recurrenceRule != null &&
          recurrenceRule.isNotEmpty) {
        dueDate = calculateNextDueDate(
          recurrenceRule,
          DateTime.now().toUtc(),
        );
      }

      String? googleTaskId;
      if (taskService != null) {
        try {
          final createdTask = await taskService!.createTask(
            taskName,
            description,
            dueDate,
          );
          googleTaskId = createdTask.id;
        } catch (e) {
          print('Failed to sync to Google Tasks: $e');
        }
      }

      final chore = ChoreTask(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        taskName: taskName,
        description: description,
        dueDate: dueDate,
        difficulty: difficulty is int ? difficulty : 1,
        priority: priority,
        recurrenceRule: recurrenceRule,
        googleTaskId: googleTaskId,
      );

      await sheetService.addChore(chore);

      replies.add(
        dueDate != null
            ? 'I have added the task "$taskName" '
                'due on ${_formatDate(dueDate)}. ✅'
            : 'I have added the task "$taskName" (No due date). ✅',
      );
    }
  }

  Future<void> _handleRemoveChore(
      Map<String, Object?> actionData, List<String> replies) async {
    final taskName = actionData['taskName'] as String?;
    if (taskName != null && taskName.isNotEmpty) {
      final googleTaskId = await sheetService.removeChoreByName(
        taskName,
      );
      if (googleTaskId != null) {
        replies.add(
          'I have removed the task "$taskName" from the sheet. 🗑️',
        );
        if (googleTaskId != 'no_google_task_id' && taskService != null) {
          try {
            await taskService!.deleteTask(googleTaskId);
            replies.add('And deleted it from Google Tasks! ✅');
          } catch (e) {
            replies.add('Failed to delete from Google Tasks: $e');
          }
        }
      } else {
        replies.add(
          'I understood you want to remove a task, '
          'but I couldn\'t find '
          'a task named "$taskName" in your list.',
        );
      }
    } else {
      replies.add(
        'I understood you want to remove a task, '
        'but I didn\'t catch the name.',
      );
    }
  }

  Future<void> _handleCompleteChore(
      Map<String, Object?> actionData, List<String> replies) async {
    final taskName = actionData['taskName'] as String?;
    if (taskName != null && taskName.isNotEmpty) {
      final chores = await sheetService.getChores();
      final taskIndex = chores.indexWhere(
        (c) => c.taskName.toLowerCase() == taskName.toLowerCase(),
      );
      if (taskIndex != -1) {
        final task = chores[taskIndex];
        final nextOccurrenceMsg = await markTaskComplete(task);
        var reply = 'I have marked the task "$taskName" as completed! ✅';
        if (nextOccurrenceMsg != null) {
          reply += '\n$nextOccurrenceMsg';
        }
        reply += '\n(Let me know if that\'s incorrect '
            'or if it\'s not done yet!)';
        replies.add(reply);
      } else {
        replies.add(
          'I understood you want to complete a task, '
          'but I couldn\'t find '
          'a task named "$taskName" in your active list.',
        );
      }
    } else {
      replies.add(
        'I understood you want to complete a task, '
        'but I didn\'t catch the name.',
      );
    }
  }

  Future<void> _handleUpdateChoreDueDate(
      Map<String, Object?> actionData, List<String> replies) async {
    final taskName = actionData['taskName'] as String?;
    final dueDateStr = actionData['dueDate'] as String?;
    
    if (taskName != null &&
        taskName.isNotEmpty &&
        dueDateStr != null &&
        dueDateStr.isNotEmpty) {
      DateTime? dueDate;
      try {
        dueDate = DateTime.parse(dueDateStr).toUtc();
      } catch (e) {
        replies.add('Failed to parse the new due date: $dueDateStr');
        return;
      }
      
      final chores = await sheetService.getChores();
      final taskIndex = chores.indexWhere(
        (c) => c.taskName.toLowerCase() == taskName.toLowerCase(),
      );
      
      if (taskIndex != -1) {
        final task = chores[taskIndex];
        final updatedTask = ChoreTask(
          id: task.id,
          taskName: task.taskName,
          description: task.description,
          dueDate: dueDate,
          difficulty: task.difficulty,
          priority: task.priority,
          recurrenceRule: task.recurrenceRule,
          lastCompletedAt: task.lastCompletedAt,
          googleTaskId: task.googleTaskId,
        );
        
        await sheetService.updateChore(updatedTask);
        
        if (taskService != null && task.googleTaskId != null) {
          try {
            await taskService!.updateTask(task.googleTaskId!, due: dueDate);
          } catch (e) {
            print('Failed to update Google Tasks: $e');
          }
        }
        
        replies.add(
          'I have updated the due date for "$taskName" to '
          '${_formatDate(dueDate)}. ✅',
        );
      } else {
        replies.add(
          'I understood you want to update a task, but I couldn\'t find '
          'a task named "$taskName" in your list.',
        );
      }
    } else {
      replies.add(
        'I understood you want to update a task, but I didn\'t catch '
        'the name or the new due date.',
      );
    }
  }

  /// Calls the Gemini model with the given [prompt] and returns
  /// the text response.
  Future<String> callGemini(String prompt) async {
    final response = await ai.generate<Object?, String>(
      model: googleAI.gemini('gemini-2.5-flash'),
      prompt: prompt,
    );
    return response.text;
  }

  /// Performs bi-directional synchronization between Google Tasks and the
  /// Sheet.
  Future<void> syncWithGoogleTasks() async {
    if (taskService == null) return;
    try {
      final googleTasks = await taskService!.getUpcomingTasks();
      final chores = await sheetService.getChores();

      final sheetTaskIds = chores
          .map((c) => c.googleTaskId)
          .where((id) => id != null)
          .toSet();

      for (final task in googleTasks) {
        if (task.id != null && !sheetTaskIds.contains(task.id)) {
          await _addGoogleTaskToSheet(task);
        }
      }

      for (final chore in chores) {
        if (chore.googleTaskId != null &&
            !googleTasks.any((t) => t.id == chore.googleTaskId)) {
          await _syncChoreCompletion(chore);
        }
      }
    } catch (e) {
      print('Error during syncWithGoogleTasks: \$e');
    }
  }

  Future<void> _addGoogleTaskToSheet(tasks.Task task) async {
    final newChore = ChoreTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      taskName: task.title ?? 'Unnamed Task',
      description: task.notes ?? '',
      dueDate: task.due != null ? DateTime.parse(task.due!).toUtc() : null,
      difficulty: 3,
      priority: 'medium',
      googleTaskId: task.id,
    );
    await sheetService.addChore(newChore);
    print('Synced new task from Google Tasks: ${task.title}');
  }

  Future<void> _syncChoreCompletion(ChoreTask chore) async {
    try {
      final isCompleted = await taskService!.isTaskCompleted(
        chore.googleTaskId!,
      );
      if (isCompleted) {
        await markTaskComplete(chore);
        print(
          'Synced completion from Google Tasks for: ${chore.taskName}',
        );
      }
    } catch (e) {
      print(
        'Failed to check completion for task ${chore.googleTaskId}: $e',
      );
    }
  }

  /// Marks a [task] as complete in the Sheet and Google Tasks, and creates
  /// the next occurrence if it is recurring.
  Future<String?> markTaskComplete(ChoreTask task) async {
    final now = DateTime.now().toUtc();

    final updatedTask = ChoreTask(
      id: task.id,
      taskName: task.taskName,
      description: task.description,
      dueDate: task.dueDate,
      difficulty: task.difficulty,
      priority: task.priority,
      recurrenceRule: task.recurrenceRule,
      lastCompletedAt: now,
      googleTaskId: task.googleTaskId,
    );

    await sheetService.updateChore(updatedTask);

    if (taskService != null && task.googleTaskId != null) {
      try {
        await taskService!.updateTaskStatus(task.googleTaskId!, true);
      } catch (e) {
        print('Failed to mark Google Tasks as completed: $e');
      }
    }

    if (task.recurrenceRule != null && task.recurrenceRule!.isNotEmpty) {
      final nextDue = calculateNextDueDate(task.recurrenceRule!, now);
      if (nextDue != null) {
        String? googleTaskId;
        if (taskService != null) {
          try {
            final createdTask = await taskService!.createTask(
              task.taskName,
              task.description,
              nextDue,
            );
            googleTaskId = createdTask.id;
          } catch (e) {
            print('Failed to sync recurring task to Google Tasks: \$e');
          }
        }

        final nextTask = ChoreTask(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          taskName: task.taskName,
          description: task.description,
          dueDate: nextDue,
          difficulty: task.difficulty,
          priority: task.priority,
          recurrenceRule: task.recurrenceRule,
          googleTaskId: googleTaskId,
        );
        await sheetService.addChore(nextTask);
        return 'Recurring task! Created new occurrence due: '
            '${_formatDate(nextDue)}';
      }
    }
    return null;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'No due date';
    final localDate = date.toLocal();
    return '${localDate.year}-'
        '${localDate.month.toString().padLeft(2, '0')}-'
        '${localDate.day.toString().padLeft(2, '0')}';
  }

  /// Calculates the next due date based on a recurrence [rule] and a
  /// [baseDate].
  DateTime? calculateNextDueDate(String rule, DateTime baseDate) {
    final lowerRule = rule.toLowerCase().trim();
    if (lowerRule.isEmpty) return null;

    final regExp = RegExp(r'every (\d+) (days|weeks|months)');
    final match = regExp.firstMatch(lowerRule);

    if (match != null) {
      final quantity = int.tryParse(match.group(1)!) ?? 1;
      final unit = match.group(2)!;

      if (unit == 'days') {
        return baseDate.add(Duration(days: quantity));
      } else if (unit == 'weeks') {
        return baseDate.add(Duration(days: quantity * 7));
      } else if (unit == 'months') {
        return DateTime(baseDate.year, baseDate.month + quantity, baseDate.day);
      }
    }

    if (lowerRule == 'every day') return baseDate.add(const Duration(days: 1));
    if (lowerRule == 'every week') return baseDate.add(const Duration(days: 7));
    if (lowerRule == 'every month') {
      return DateTime(baseDate.year, baseDate.month + 1, baseDate.day);
    }

    return null;
  }
}
