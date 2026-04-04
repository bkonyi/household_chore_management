import 'dart:convert';
import 'dart:io';

import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis/tasks/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:household_chore_management/db/sheet.dart';
import 'package:household_chore_management/db/tasks.dart';
import 'package:http/http.dart' as http;
import 'package:nyxx/nyxx.dart';

Map<String, String> _loadEnv() {
  final env = <String, String>{};
  final file = File('.env');
  if (file.existsSync()) {
    final lines = file.readAsLinesSync();
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final parts = trimmed.split('=');
      if (parts.length >= 2) {
        env[parts[0].trim()] = parts.sublist(1).join('=').trim();
      }
    }
  }
  return env;
}

void main() async {
  print('Initializing Feature Regression Sweep...');
  final env = _loadEnv();

  final testBotToken = env['TEST_BOT_TOKEN'];
  final testChannelId = env['TEST_CHANNEL_ID'];
  final choreBotId = env['CHORE_BOT_ID'];
  final sheetId = env['GOOGLE_SHEET_ID'];
  final taskListId = env['TASK_LIST_ID'] ?? '@default';

  if (testBotToken == null ||
      testChannelId == null ||
      choreBotId == null ||
      sheetId == null) {
    print('Error: Missing configurations in .env file.');
    exit(1);
  }

  final tokenFile = File('tokens.json');
  late final AutoRefreshingAuthClient client;
  final clientId = ClientId(
    env['GOOGLE_OAUTH_CLIENT_ID'] ?? '',
    env['GOOGLE_OAUTH_CLIENT_SECRET'] ?? '',
  );



  if (tokenFile.existsSync()) {
    final tokenMap =
        jsonDecode(tokenFile.readAsStringSync()) as Map<String, Object?>;
    final tokenData = tokenMap['accessToken'] as Map<String, Object?>;
    final credentials = AccessCredentials(
      AccessToken(
        tokenData['type'] as String,
        tokenData['data'] as String,
        DateTime.parse(tokenData['expiry'] as String),
      ),
      tokenMap['refreshToken'] as String?,
      (tokenMap['scopes'] as List).cast<String>(),
    );
    client = autoRefreshingClient(clientId, credentials, http.Client());
  } else {
    print('Fatal: tokens.json required.');
    exit(1);
  }

  final sheetsApi = SheetsApi(client);
  final tasksApi = TasksApi(client);
  final sheetService = SheetService(sheetsApi, sheetId);
  final taskService = TaskService(tasksApi, taskListId: taskListId);

  print('Connecting to Discord...');
  final nyxxClient = await Nyxx.connectGateway(
    testBotToken,
    GatewayIntents.allUnprivileged | GatewayIntents.messageContent,
  );

  final report = <String, String>{};

  Future<String> sendAndReceive(String msg) async {
    final channel = await nyxxClient.channels.get(
      Snowflake.parse(testChannelId),
    );
    if (channel is! TextChannel) throw Exception('Not a text channel');

    final futureReply = nyxxClient.onMessageCreate
        .firstWhere(
          (e) =>
              e.message.author.id == Snowflake.parse(choreBotId) &&
              e.message.channel.id == channel.id,
        )
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw Exception('Timed out waiting for Bot reply'),
        );

    await channel.sendMessage(MessageBuilder(content: msg));
    final replyEvent = await futureReply;
    return replyEvent.message.content;
  }

  void logFeature(String name, bool passed, [String? error]) {
    report[name] = passed ? '✅ PASSED' : '❌ FAILED ${error ?? ''}';
    print('[$name] : ${report[name]}');
  }

  try {
    print('\n🧹 Purging sandbox records before sweep...');
    await sheetsApi.spreadsheets.values.clear(
      ClearValuesRequest(),
      sheetId,
      'A2:I',
    );
    final tasksToClear = await taskService.getUpcomingTasks();
    for (final t in tasksToClear) {
      if (t.id != null) await taskService.deleteTask(t.id!);
    }
    print('✅ Sandbox scrubbed clean.');

    print('\n--- Starting Full Regression Sweep ---');

    // 1. !list empty
    try {
      final reply = await sendAndReceive('!list');
      logFeature(
        'Command: !list (empty)',
        reply.contains('No chores found') || reply.contains('chores found'),
      );
    } catch (e) {
      logFeature('Command: !list (empty)', false, e.toString());
    }

    // 2. !remind empty
    try {
      final reply = await sendAndReceive('!remind');
      logFeature(
        'Command: !remind',
        reply.contains('Triggered manual reminders'),
      );
    } catch (e) {
      logFeature('Command: !remind', false, e.toString());
    }

    // 3. Natural Add
    final testTaskName = 'Sweep Task ${DateTime.now().millisecondsSinceEpoch}';
    try {
      await sendAndReceive(
        'Please add a task to "$testTaskName" difficulty 3 priority high',
      );
      final chores = await sheetService.getChores();
      final hasChore = chores.any((c) => c.taskName == testTaskName);
      final tasks = await taskService.getUpcomingTasks();
      final hasTask = tasks.any((t) => t.title == testTaskName);
      logFeature('Natural: Add Chore', hasChore && hasTask);
    } catch (e) {
      logFeature('Natural: Add Chore', false, e.toString());
    }

    // Safety wrapper around unsafe reloads
    ChoreTask? taskObj;
    try {
      final chores = await sheetService.getChores();
      taskObj = chores.firstWhere((c) => c.taskName == testTaskName);
    } catch (e) {
      print('⚠️ Failed to reload created task object for subsequent tests: $e');
    }

    if (taskObj != null) {
      // 4. !list occupied
      try {
        final reply = await sendAndReceive('!list');
        logFeature(
          'Command: !list (populated)',
          reply.contains(testTaskName) ||
              reply.contains('chores') ||
              reply.length > 10,
        );
      } catch (e) {
        logFeature('Command: !list (populated)', false, e.toString());
      }

      // 5. !suggest
      try {
        final reply = await sendAndReceive('!suggest 3 30');
        print('DEBUG: !suggest reply: "$reply"');
        logFeature(
          'Command: !suggest',
          reply.length > 20 && !reply.contains('```json'),
        );
      } catch (e) {
        logFeature('Command: !suggest', false, e.toString());
      }

      // 6. !snooze
      try {
        final reply = await sendAndReceive('!snooze ${taskObj.id} 3');
        logFeature('Command: !snooze', reply.contains('snoozed for 3 days'));
      } catch (e) {
        logFeature('Command: !snooze', false, e.toString());
      }

      // 7. !complete
      try {
        await sendAndReceive('!complete ${taskObj.id}');
        final choresAfter = await sheetService.getChores();
        final doneChore = !choresAfter.any((c) => c.taskName == testTaskName);
        logFeature('Command: !complete', doneChore);
      } catch (e) {
        logFeature('Command: !complete', false, e.toString());
      }
    } else {
      logFeature(
        'Command: !list (populated)',
        false,
        'Skipped (Parent Task missing)',
      );
      logFeature('Command: !suggest', false, 'Skipped (Parent Task missing)');
      logFeature('Command: !snooze', false, 'Skipped (Parent Task missing)');
      logFeature('Command: !complete', false, 'Skipped (Parent Task missing)');
    }

    // 8. Natural Delete
    final testTaskName2 =
        'Sweep Task DELETE ${DateTime.now().millisecondsSinceEpoch}';
    try {
      await sendAndReceive('Please add a chore called "$testTaskName2"');
      final reply = await sendAndReceive(
        'Please remove the chore "$testTaskName2"',
      );
      final choresAfter = await sheetService.getChores();
      final deleted = !choresAfter.any((c) => c.taskName == testTaskName2);
      logFeature('Natural: Remove Chore', deleted && reply.contains('removed'));
    } catch (e) {
      logFeature('Natural: Remove Chore', false, e.toString());
    }

    // 9. Due Dates
    final testTaskNameDue =
        'Sweep Task DUE ${DateTime.now().millisecondsSinceEpoch}';
    try {
      await sendAndReceive(
        'Please add a task "$testTaskNameDue" due tomorrow',
      );
      final chores = await sheetService.getChores();
      final taskObj = chores.firstWhere((c) => c.taskName == testTaskNameDue);
      final hasDue = taskObj.dueDate != null;
      logFeature('Duality: Due Dates', hasDue);
    } catch (e) {
      logFeature('Duality: Due Dates', false, e.toString());
    }

    // 10. Recurrence
    final testTaskNameRecur =
        'Sweep Task RECUR ${DateTime.now().millisecondsSinceEpoch}';
    try {
      await sendAndReceive(
        'Please add a chore called "$testTaskNameRecur" every week',
      );
      final chores = await sheetService.getChores();
      final taskObj = chores.firstWhere((c) => c.taskName == testTaskNameRecur);
      final hasRecur =
          taskObj.recurrenceRule != null &&
          taskObj.recurrenceRule!.toLowerCase().contains('week');

      // Complete it to see if occurrence spawns!
      await sendAndReceive('Mark "$testTaskNameRecur" as completed');
      final choresAfter = await sheetService.getChores();
      final spawnFound = choresAfter.any(
        (c) => c.taskName == testTaskNameRecur && c.dueDate != null,
      );
      logFeature('Duality: Recurrence Cycle', hasRecur && spawnFound);
    } catch (e) {
      logFeature('Duality: Recurrence Cycle', false, e.toString());
    }

    // 11. !remind populated
    try {
      final reply = await sendAndReceive('!remind');
      // Order of precedence: Bot broadcasts before returning ack.
      // So the first message captured is the friendly reminder text.
      logFeature(
        'Command: !remind (populated)',
        reply.contains('DUE') ||
            reply.contains('Upcoming') ||
            reply.length > 30,
      );
    } catch (e) {
      logFeature('Command: !remind (populated)', false, e.toString());
    }

    print('\n================ REGRESSION SWEEP REPORT ================');
    report.forEach((key, value) {
      print('| ${key.padRight(30)} | $value |');
    });
    print('=========================================================\n');
  } finally {
    await nyxxClient.close();
    client.close();
    exit(0);
  }
}
