import 'dart:async';
import 'package:nyxx/nyxx.dart';
import '../db/sheet.dart';
import '../db/tasks.dart';
import '../genkit/flows.dart';
import '../services/weather.dart';

/// A Discord bot that interacts with the user to manage chores.
class DiscordBot {
  /// The Discord bot token.
  final String token;

  /// The service used to interact with the Google Sheet database.
  final ChoreDatabase sheetService;

  /// The service used for AI operations.
  final GenKitService genKitService;

  /// The service used to interact with Google Tasks (optional).
  final TaskService? taskService;

  /// The Nyxx client instance.
  late final NyxxGateway client;

  /// The ID of the Discord channel where reminders will be sent.
  final String announcementChannelId; // Channel for reminders

  /// The ID of the bot user.
  Snowflake? _botId;

  /// Conversation history per channel.
  final Map<String, List<String>> _conversations = {};

  /// Creates a [DiscordBot].
  DiscordBot({
    required this.token,
    required this.sheetService,
    required this.genKitService,
    required this.announcementChannelId,
    this.taskService,
  });

  /// Starts the Discord bot and connects to the gateway.
  Future<void> start() async {
    client = await Nyxx.connectGateway(
      token,
      GatewayIntents.allUnprivileged | GatewayIntents.messageContent,
    );

    final botUser = await client.users.fetchCurrentUser();
    _botId = botUser.id;

    client.onMessageCreate.listen(_handleMessage);

    print('Chore Agent Bot is ready!');

    // Start periodic check for reminders (e.g., every 12 hours)
    Timer.periodic(const Duration(hours: 12), (timer) => _checkAndRemind());
  }

  void _handleMessage(MessageCreateEvent event) async {
    // Prevent the bot from responding to its own messages and creating a
    // feedback loop!
    if (event.message.author.id == _botId) return;

    final content = event.message.content.trim();
    final channelId = event.message.channelId.toString();

    final history = _conversations[channelId] ??= [];
    history.add('User: $content');

    // Limit history size
    if (history.length > 20) {
      history.removeRange(0, history.length - 20);
    }

    final reply = await getBotReply(content, history);
    if (reply.isNotEmpty) {
      history.add('Bot: $reply');
      await event.message.channel.sendMessage(MessageBuilder(content: reply));
    }
  }

  /// Gets the bot's reply for a given message content.
  Future<String> getBotReply(String content, List<String> history) async {
    if (content == '!list') {
      return _getListReply();
    } else if (content == '!remind') {
      await _checkAndRemind();
      return 'Triggered manual reminders! 🔔';
    } else if (content.startsWith('!suggest ')) {
      return _getSuggestReply(content);
    } else if (content.startsWith('!complete ')) {
      return _getCompleteReply(content);
    } else if (content.startsWith('!snooze ')) {
      return _getSnoozeReply(content);
    } else {
      return genKitService.processChat(history.join('\n'));
    }
  }

  Future<String> _getListReply() async {
    await _syncTasksToSheet(); // Synchronize before listing
    final chores = await sheetService.getChores();
    if (chores.isEmpty) {
      return 'No chores found in the tracking sheet!';
    }

    return genKitService.generateFriendlyReminder(chores);
  }

  Future<String> _getSuggestReply(String content) async {
    final parts = content.split(' ');
    if (parts.length < 3) {
      return 'Usage: `!suggest [energy_1_5] [time_mins]`';
    }

    final energy = int.tryParse(parts[1]) ?? 3;
    final time = int.tryParse(parts[2]) ?? 30;

    final chores = await sheetService.getChores();
    final matchingChores = chores.where((c) => c.difficulty <= energy).toList();

    final weatherService = WeatherService();
    final weather = await weatherService.fetchCurrentWeather();

    return genKitService.generateFriendlySuggestions(
      matchingChores,
      energy,
      time,
      weather: weather,
    );
  }

  Future<String> _getCompleteReply(String content) async {
    final parts = content.split(' ');
    if (parts.length < 2) {
      return 'Usage: `!complete [task_id]`';
    }

    final taskId = parts[1];
    final chores = await sheetService.getChores();
    final taskIndex = chores.indexWhere((c) => c.id == taskId);

    if (taskIndex == -1) {
      return 'Task with ID $taskId not found.';
    }

    final task = chores[taskIndex];
    final nextOccurrenceMsg = await genKitService.markTaskComplete(task);

    var replyMessage = 'Task "${task.taskName}" marked as completed!';
    if (nextOccurrenceMsg != null) {
      replyMessage += '\n$nextOccurrenceMsg';
    }

    return replyMessage;
  }

  Future<String> _getSnoozeReply(String content) async {
    final parts = content.split(' ');
    if (parts.length < 3) {
      return 'Usage: `!snooze [task_id] [days]`';
    }

    final taskId = parts[1];
    final days = int.tryParse(parts[2]) ?? 1;

    final chores = await sheetService.getChores();
    final taskIndex = chores.indexWhere((c) => c.id == taskId);

    if (taskIndex == -1) {
      return 'Task with ID $taskId not found.';
    }

    final task = chores[taskIndex];
    final updatedTask = ChoreTask(
      id: task.id,
      taskName: task.taskName,
      description: task.description,
      dueDate: task.dueDate?.add(Duration(days: days)),
      difficulty: task.difficulty,
      priority: task.priority,
      recurrenceRule: task.recurrenceRule,
      lastCompletedAt: task.lastCompletedAt,
      googleTaskId: task.googleTaskId,
    );

    await sheetService.updateChore(updatedTask);
    return 'Task "${task.taskName}" snoozed for $days days. '
        'New due date: ${updatedTask.dueDate?.toIso8601String() ?? 'None'}';
  }

  Future<void> _checkAndRemind() async {
    await _syncTasksToSheet(); // Synchronize before sending reminders
    final chores = await sheetService.getChores();
    final dueSoon = chores.where((c) {
      if (c.dueDate != null) {
        final localDue = c.dueDate!.toLocal();
        final nowLocal = DateTime.now().toLocal();
        final diff = localDue.difference(nowLocal).inDays;
        return diff <= 1 && diff >= 0; // Fixed diff <= 1 to match tomorrow
      }
      return false;
    }).toList();

    if (dueSoon.isNotEmpty) {
      final friendlyMessage = await genKitService.generateFriendlyReminder(
        dueSoon,
      );
      // Send to specific channel
      final channel = await client.channels.get(
        Snowflake.parse(announcementChannelId),
      );
      if (channel is TextChannel) {
        await channel.sendMessage(MessageBuilder(content: friendlyMessage));
      }
    }
  }

  Future<void> _syncTasksToSheet() async {
    if (taskService == null) return;

    final chores = await sheetService.getChores();
    for (final task in chores) {
      if (task.googleTaskId != null && task.googleTaskId!.isNotEmpty) {
        try {
          final completed = await taskService!.isTaskCompleted(
            task.googleTaskId!,
          );
          if (completed) {
            print(
              'Detected chore "${task.taskName}" completed in Google Tasks',
            );
            await genKitService.markTaskComplete(task);
          }
        } catch (e) {
          print('Failed to poll Google Tasks for "${task.taskName}": $e');
        }
      }
    }
  }
}
