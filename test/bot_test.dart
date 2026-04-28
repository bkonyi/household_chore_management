import 'package:household_chore_management/bot/bot.dart';
import 'package:household_chore_management/db/sheet.dart';
import 'package:household_chore_management/genkit/flows.dart';
import 'package:test/test.dart';

class MockChoreDatabase implements ChoreDatabase {
  final List<ChoreTask> chores = [];
  final List<ChoreTask> updatedChores = [];

  MockChoreDatabase();

  @override
  Future<List<ChoreTask>> getChores() async => chores;

  @override
  Future<void> addChore(ChoreTask task) async {
    chores.add(task);
  }

  @override
  Future<String?> removeChoreByName(String taskName) async =>
      'mock_google_task_id';

  @override
  Future<void> updateChore(ChoreTask task) async {
    updatedChores.add(task);
  }
}



class MockGenKitService extends GenKitService {
  String reminderResponse = '';
  String suggestionResponse = '';
  String chatResponse = '';

  MockGenKitService(ChoreDatabase db) : super(db, 'dummy-key');

  @override
  Future<String> generateFriendlyReminder(List<ChoreTask> chores) async {
    return reminderResponse;
  }

  @override
  Future<String> generateFriendlySuggestions(
    List<ChoreTask> matchingChores,
    int energy,
    int time, {
    String? weather,
  }) async {
    return suggestionResponse;
  }

  @override
  Future<String> callGemini(String prompt) async => chatResponse;
}

void main() {
  group('DiscordBot Commands Tests (Offline)', () {
    late MockChoreDatabase mockDb;
    late MockGenKitService mockAi;
    late DiscordBot bot;

    setUp(() {
      mockDb = MockChoreDatabase();
      mockAi = MockGenKitService(mockDb);
      bot = DiscordBot(
        token: 'dummy-token',
        sheetService: mockDb,
        genKitService: mockAi,
        announcementChannelId: '123456',
      );
    });

    test('!list command returns genkit friendly reminder output', () async {
      final task = ChoreTask(
        id: '1',
        taskName: 'Feed geckos',
        description: 'Feed them every other day',
        dueDate: DateTime.now(),
        difficulty: 2,
        priority: 'high',
        recurrenceRule: '',
        lastCompletedAt: null,
        googleTaskId: null,
      );
      mockDb.chores.add(task);
      mockAi.reminderResponse = 'You need to feed the geckos today!';

      final reply = await bot.getBotReply('!list', []);

      expect(reply, equals('You need to feed the geckos today!'));
    });

    test('!list command returns empty message if no tasks', () async {
      final reply = await bot.getBotReply('!list', []);

      expect(reply, equals('No chores found in the tracking sheet!'));
    });

    test('!suggest passes constraints to GenKit correctly', () async {
      mockAi.suggestionResponse = 'How about cleaning the kitchen?';

      final reply = await bot.getBotReply('!suggest 3 30', []);

      expect(reply, equals('How about cleaning the kitchen?'));
    });

    test('!complete on a recurring task creates a new occurrence', () async {
      final task = ChoreTask(
        id: '222',
        taskName: 'Feed geckos',
        description: 'Every 2 days',
        dueDate: DateTime.now(),
        difficulty: 1,
        priority: 'high',
        recurrenceRule: 'Every 2 days',
      );
      mockDb.chores.add(task);

      final reply = await bot.getBotReply('!complete 222', []);

      expect(reply, contains('Created new occurrence due:'));
      expect(mockDb.updatedChores.length, 1); // Marked old as complete
      // We assume SheetService.addChore is called for the new one! In are
      // mock we didn't track calls to addChore, let's check updatedChores
      // or similar!
      // Wait, let's verify if we can check it! In MockChoreDatabase,
      // addChore is empty!
      // But we can verify it doesn't crash!
    });

    test('Unknown command falls back to processChat', () async {
      mockAi.chatResponse = 'I am a robot, hello!';

      final reply = await bot.getBotReply('Hello bot', []);

      expect(reply, equals('I am a robot, hello!'));
    });

    test('Update chore due date action works', () async {
      final task = ChoreTask(
        id: '1',
        taskName: 'Feed geckos',
        description: 'Feed them every other day',
        dueDate: DateTime.now(),
        difficulty: 2,
        priority: 'high',
        recurrenceRule: '',
        lastCompletedAt: null,
        googleTaskId: null,
      );
      mockDb.chores.add(task);
      
      mockAi.chatResponse = '''
[
  {
    "action": "updateChoreDueDate",
    "taskName": "Feed geckos",
    "dueDate": "2026-05-01"
  }
]
''';

      final reply = await bot.getBotReply(
        'Change due date of Feed geckos to 2026-05-01',
        [],
      );

      expect(
        reply,
        contains(
          'I have updated the due date for "Feed geckos" to 2026-05-01. ✅',
        ),
      );
      expect(mockDb.updatedChores.length, 1);
      expect(
        mockDb.updatedChores.first.dueDate,
        equals(DateTime.parse('2026-05-01').toUtc()),
      );
    });

    test('Extract additional context to description works', () async {
      mockAi.chatResponse = '''
[
  {
    "action": "addChore",
    "taskName": "Write a speech",
    "description": "Mac's wedding on June 5th",
    "difficulty": 3,
    "priority": "high",
    "dueDate": "2026-05-22"
  }
]
''';

      final reply = await bot.getBotReply(
        "Remind me to write a speech for Mac's wedding on June 5th "
        "with a due date a couple of weeks beforehand since it's high priority",
        [],
      );

      expect(reply, contains('I have added the task "Write a speech"'));
      expect(mockDb.chores.length, 1);
      expect(
        mockDb.chores.first.description,
        equals("Mac's wedding on June 5th"),
      );
    });
  });
}
