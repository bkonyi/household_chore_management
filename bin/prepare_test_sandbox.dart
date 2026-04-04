import 'dart:convert';
import 'dart:io';

import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis/tasks/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

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
  Platform.environment.forEach((key, value) {
    if (!env.containsKey(key)) {
      env[key] = value;
    }
  });
  return env;
}

void main() async {
  print('Initializing Maintenance Sandbox Creator...');
  final env = _loadEnv();

  final tokenFile = File('tokens.json');
  late final AutoRefreshingAuthClient client;

  final clientId = ClientId(
    env['GOOGLE_OAUTH_CLIENT_ID'] ?? '',
    env['GOOGLE_OAUTH_CLIENT_SECRET'] ?? '',
  );



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

    client = autoRefreshingClient(
      clientId,
      credentials,
      http.Client(),
    );
  } else {
    print(
      'Failed to find tokens.json cache! '
      'This script requires authorized tokens.',
    );
    exit(1);
  }

  final sheetsApi = SheetsApi(client);
  final tasksApi = TasksApi(client);

  try {
    print('Creating sandbox Google Spreadsheet...');
    final spreadsheet = Spreadsheet(
      properties: SpreadsheetProperties(title: 'Household Chore Testing Box'),
    );
    final createdSheet = await sheetsApi.spreadsheets.create(spreadsheet);
    print('\n✅ SANDBOX_SPREADSHEET_ID: ${createdSheet.spreadsheetId}');

    print('\nCreating sandbox Google Task List...');
    final taskList = TaskList(title: 'Household Chore Verification Box');
    final createdTaskList = await tasksApi.tasklists.insert(taskList);
    print('✅ SANDBOX_TASK_LIST_ID: ${createdTaskList.id}');

    print('\n--- Paste these into your .env file! ---');
  } catch (e) {
    print('\n❌ Failed to spawn sandboxes: $e');
  } finally {
    client.close();
  }
}
