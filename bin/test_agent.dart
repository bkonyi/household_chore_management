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
  // Fallback to system env
  Platform.environment.forEach((key, value) {
    if (!env.containsKey(key)) {
      env[key] = value;
    }
  });
  return env;
}

void main() async {
  final env = _loadEnv();

  final testBotToken = env['TEST_BOT_TOKEN'];
  var testChannelId = env['TEST_CHANNEL_ID'];
  var choreBotId = env['CHORE_BOT_ID'];
  final sheetId = env['GOOGLE_SHEET_ID']; // Main sheet or test sheet

  if (testBotToken == null ||
      testChannelId == null ||
      choreBotId == null ||
      sheetId == null) {
    print(
      'Error: TEST_BOT_TOKEN, TEST_CHANNEL_ID, CHORE_BOT_ID, '
      'and GOOGLE_SHEET_ID must be set in your .env file or environment.',
    );
    exit(1);
  }

  print('Initializing Test Agent...');

  // Initialize Read-Only Auth Client for Verification
  final tokenFile = File('tokens.json');
  late final AutoRefreshingAuthClient client;

  final clientId = ClientId(
    env['GOOGLE_OAUTH_CLIENT_ID'] ?? '',
    env['GOOGLE_OAUTH_CLIENT_SECRET'] ?? '',
  );

  final scopes = [
    'https://www.googleapis.com/auth/spreadsheets',
    'https://www.googleapis.com/auth/tasks',
  ];

  if (tokenFile.existsSync()) {
    final tokenJson = tokenFile.readAsStringSync();
    final tokenMap = jsonDecode(tokenJson) as Map<String, Object?>;
    final tokenData = tokenMap['accessToken'] as Map<String, Object?>;

    final accessToken = AccessToken(
      tokenData['type'] as String,
      tokenData['data'] as String,
      DateTime.parse(tokenData['expiry'] as String),
    );

    final credentials = AccessCredentials(
      accessToken,
      tokenMap['refreshToken'] as String?,
      (tokenMap['scopes'] as List).cast<String>(),
      idToken: tokenMap['idToken'] as String?,
    );

    client = autoRefreshingClient(clientId, credentials, http.Client());
  } else {
    // Falls back to user consent if no token cache found
    client = await clientViaUserConsent(clientId, scopes, (url) {
      print(
        'Please go to the following URL and grant access (for Test Agent):',
      );
      print('  $url');
      print('');
      print('After approving, please enter the authorization code here.');
    });
    // Save token state
    final credentials = client.credentials;
    final tokenMap = {
      'accessToken': credentials.accessToken.toJson(),
      'refreshToken': credentials.refreshToken,
      'scopes': credentials.scopes,
      'idToken': credentials.idToken,
    };
    tokenFile.writeAsStringSync(jsonEncode(tokenMap));
  }

  final sheetsApi = SheetsApi(client);
  final tasksApi = TasksApi(client);
  final sheetService = SheetService(sheetsApi, sheetId);
  final taskListId = env['TASK_LIST_ID'] ?? '@default';
  final taskService = TaskService(tasksApi, taskListId: taskListId);

  print('Connecting to Discord as Test Agent...');
  final nyxxClient = await Nyxx.connectGateway(
    testBotToken,
    GatewayIntents.allUnprivileged | GatewayIntents.messageContent,
  );

  print('Test Agent Connected! Running scenarios...');

  try {
    final testChoreName = 'Test Task ${DateTime.now().millisecondsSinceEpoch}';
    print('--- Scenario A: Add Task ---');
    print('Adding task "$testChoreName"...');

    final addReply = await sendAndReceive(
      nyxxClient,
      testChannelId,
      choreBotId,
      'Can you please add a task to "$testChoreName" '
      'with description "Automation test"?',
    );
    print('Bot replied: $addReply');

    // Verify Sheet
    final chores = await sheetService.getChores();
    chores.firstWhere(
      (c) => c.taskName == testChoreName,
      orElse: () => throw Exception('Chore not found in sheet active list'),
    );
    print('Verified: Chore row exists in Sheet!');

    // Verify Task
    final tasks = await taskService.getUpcomingTasks();
    final addedTask = tasks.firstWhere(
      (t) => t.title == testChoreName,
      orElse: () =>
          throw Exception('Task not found in Google Tasks upcoming list'),
    );
    print('Verified: Google Task exists!');

    print('--- Scenario B: Complete Task ---');
    print('Completing task "$testChoreName"...');

    final completeReply = await sendAndReceive(
      nyxxClient,
      testChannelId,
      choreBotId,
      'I am done with "$testChoreName"! Mark it as completed please.',
    );
    print('Bot replied: $completeReply');

    // Verify Sheet
    final choresAfterComplete = await sheetService.getChores();
    final choreCompleted = !choresAfterComplete.any(
      (c) => c.taskName == testChoreName,
    );
    expect(choreCompleted, true, 'Chore should be removed from active list');

    // Verify Task
    final isCompleted = await taskService.isTaskCompleted(addedTask.id!);
    expect(isCompleted, true, 'Google Task should be marked completed');
    print('Verified: Task completed in both Sheet and Google Tasks!');

    print('--- Scenario C: Delete Task ---');
    final testChoreName2 =
        'Test Task DELETE ${DateTime.now().millisecondsSinceEpoch}';
    print('Adding dynamic task "$testChoreName2" for deletion test...');

    await sendAndReceive(
      nyxxClient,
      testChannelId,
      choreBotId,
      'Please add a chore called "$testChoreName2".',
    );

    print('Deleting task "$testChoreName2"...');
    final deleteReply = await sendAndReceive(
      nyxxClient,
      testChannelId,
      choreBotId,
      'I don\'t need the chore "$testChoreName2" anymore. Delete it please.',
    );
    print('Bot replied: $deleteReply');

    // Verify Sheet
    final choresAfterDelete = await sheetService.getChores();
    final choreDeleted = !choresAfterDelete.any(
      (c) => c.taskName == testChoreName2,
    );
    expect(choreDeleted, true, 'Chore should be deleted from sheet');

    // Verify Task
    final tasksAfterDelete = await taskService.getUpcomingTasks();
    final taskDeleted = !tasksAfterDelete.any((t) => t.title == testChoreName2);
    expect(taskDeleted, true, 'Google Task should be deleted');
    print('Verified: Task deleted from both Sheet and Google Tasks!');

    print('--- Scenario D: Sync Task from Google Tasks ---');
    final testChoreName3 =
        'Test Task SYNC ${DateTime.now().millisecondsSinceEpoch}';
    print('Creating task directly in Google Tasks "$testChoreName3"...');

    final externalTask = await taskService.createTask(
      testChoreName3,
      'Created externally (e.g. Google Home)',
      DateTime.now().add(const Duration(days: 1)),
    );

    print('Triggering sync by asking bot...');
    final syncReply = await sendAndReceive(
      nyxxClient,
      testChannelId,
      choreBotId,
      'What chores do I have?',
    );
    print('Bot replied: $syncReply');

    // Verify Sheet
    final choresAfterSync = await sheetService.getChores();
    final choreSynced = choresAfterSync.any(
      (c) => c.taskName == testChoreName3,
    );

    // Cleanup first to avoid leaving junk if verification fails
    print('Cleaning up synced task...');
    await sheetService.removeChoreByName(testChoreName3);
    await taskService.deleteTask(externalTask.id!);

    expect(choreSynced, true, 'Chore should be imported into the sheet');
    print('Verified: Task synced and cleaned up!');

    print('--- Scenario E: Add Task in Past ---');
    final testChoreName4 =
        'Test Task PAST \${DateTime.now().millisecondsSinceEpoch}';
    print('Attempting to add task in the past "$testChoreName4"...');

    final pastReply = await sendAndReceive(
      nyxxClient,
      testChannelId,
      choreBotId,
      'Please add a chore called "$testChoreName4" due yesterday.',
    );
    print('Bot replied: $pastReply');

    expect(
      pastReply.contains('I cannot add tasks in the past'),
      true,
      'Bot should reject past task',
    );

    // Verify Sheet (should not exist)
    final choresAfterPast = await sheetService.getChores();
    final choreExists = choresAfterPast.any(
      (c) => c.taskName == testChoreName4,
    );
    expect(choreExists, false, 'Chore should not be added to sheet');

    print('Verified: Task in the past was rejected and not added!');

    print('\n🎉 All live suite scenarios PASSED! 🎉');
  } catch (e) {
    print('\n❌ Verification Failed with Error: $e ❌');
  }

  print('All tests completed or skipped. Shutting down...');
  await nyxxClient.close();
  client.close();
  exit(0);
}

Future<String> sendAndReceive(
  NyxxGateway client,
  String testChannelId,
  String choreBotId,
  String content,
) async {
  final channelId = Snowflake.parse(testChannelId);
  final botId = Snowflake.parse(choreBotId);

  final replyFuture = client.onMessageCreate
      .where(
        (event) =>
            event.message.channel.id == channelId &&
            event.message.author.id == botId,
      )
      .map((event) => event.message.content)
      .first;

  final channel = await client.channels.fetch(channelId) as TextChannel;
  await channel.sendMessage(MessageBuilder(content: content));

  return await replyFuture.timeout(const Duration(seconds: 15));
}

void expect(Object? actual, Object? expected, String message) {
  if (actual != expected) {
    throw Exception(
      'Assertion failed: Expected $expected, got $actual. $message',
    );
  }
}
