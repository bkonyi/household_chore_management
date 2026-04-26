import 'dart:convert';
import 'dart:io';

import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis/tasks/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:household_chore_management/bot/bot.dart';
import 'package:household_chore_management/db/sheet.dart';
import 'package:household_chore_management/db/tasks.dart';
import 'package:household_chore_management/genkit/flows.dart';
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
  // Fallback to system env
  Platform.environment.forEach((key, value) {
    if (!env.containsKey(key)) {
      env[key] = value;
    }
  });
  return env;
}

AccessCredentials _credentialsFromMap(Map<String, Object?> tokenMap) {
  final tokenData = tokenMap['accessToken'] as Map<String, Object?>;
  final accessToken = AccessToken(
    tokenData['type'] as String,
    tokenData['data'] as String,
    DateTime.parse(tokenData['expiry'] as String),
  );
  return AccessCredentials(
    accessToken,
    tokenMap['refreshToken'] as String?,
    (tokenMap['scopes'] as List).cast<String>(),
    idToken: tokenMap['idToken'] as String?,
  );
}

void main() async {
  final env = _loadEnv();

  // Read environment variables
  final discordToken = env['DISCORD_TOKEN'] ?? '';
  final sheetId = env['GOOGLE_SHEET_ID'] ?? '';
  final geminiApiKey = env['GEMINI_API_KEY'] ?? '';
  final channelId = env['DISCORD_CHANNEL_ID'] ?? '0'; // For reminders

  if (discordToken.isEmpty || sheetId.isEmpty || geminiApiKey.isEmpty) {
    print(
      'Warning: DISCORD_TOKEN, GOOGLE_SHEET_ID, or GEMINI_API_KEY is missing. '
      'The app may fail if these are not provided via environment variables on Fly.io.',
    );
  }

  print('Starting Chore Agent...');

  // Initialize OAuth Client for Google APIs
  final tokenFile = File('tokens.json');
  late final AutoRefreshingAuthClient client;



  // Parse ClientId from JSON
  // Expecting format:
  // {"installed": {"client_id": "...", "client_secret": "..."}}
  // We use the provided credentials directly for simplicity and robustness.
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
    client = autoRefreshingClient(clientId, _credentialsFromMap(tokenMap), http.Client());
  } else if (env['GOOGLE_TOKENS_JSON'] != null) {
    final tokenJson = env['GOOGLE_TOKENS_JSON']!;
    final tokenMap = jsonDecode(tokenJson) as Map<String, Object?>;
    client = autoRefreshingClient(clientId, _credentialsFromMap(tokenMap), http.Client());
  } else {
    client = await clientViaUserConsent(clientId, scopes, (url) {
      print('Please go to the following URL and grant access:');
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

  // Initialize Services
  final sheetsApi = SheetsApi(client);
  final sheetService = SheetService(sheetsApi, sheetId);
  final tasksApi = TasksApi(client);
  final taskListId = env['TASK_LIST_ID'] ?? '@default';
  final taskService = TaskService(tasksApi, taskListId: taskListId);
  final genKitService = GenKitService(
    sheetService,
    geminiApiKey,
    taskService: taskService,
  );

  // Initialize and Start Discord Bot
  final bot = DiscordBot(
    token: discordToken,
    sheetService: sheetService,
    genKitService: genKitService,
    announcementChannelId: channelId,
    taskService: taskService,
  );

  await bot.start();
}
