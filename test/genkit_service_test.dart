import 'package:household_chore_management/db/sheet.dart';
import 'package:household_chore_management/genkit/flows.dart';
import 'package:test/test.dart';

// Custom Mock for ChoreDatabase using standard Dart interfaces
class MockSheetService implements ChoreDatabase {
  final List<ChoreTask> addedChores = [];
  final List<String> removedChores = [];
  final List<ChoreTask> chores = [];

  MockSheetService();

  @override
  Future<void> addChore(ChoreTask task) async {
    addedChores.add(task);
  }

  @override
  Future<void> updateChore(ChoreTask task) async {
    // No-op for this mock
  }

  @override
  Future<String?> removeChoreByName(String taskName) async {
    removedChores.add(taskName);
    return 'mock_google_task_id'; // Assume success for test
  }

  @override
  Future<List<ChoreTask>> getChores() async {
    return chores;
  }
}

// Custom Mock for GenKitService overriding Gemini call
class TestGenKitService extends GenKitService {
  String mockResponse = '';

  TestGenKitService(MockSheetService sheetService)
    : super(sheetService, 'dummy-key');

  @override
  Future<String> callGemini(String prompt) async {
    return mockResponse;
  }
}

void main() {
  group('GenKitService Tests (No live API calls)', () {
    late MockSheetService mockSheet;
    late TestGenKitService testService;

    setUp(() {
      mockSheet = MockSheetService();
      testService = TestGenKitService(mockSheet);
    });

    test('Correctly parses natural language add task to JSON', () async {
      testService.mockResponse = '''
{
  "action": "addChore",
  "taskName": "Feed cresties",
  "description": "Feed crested geckos every other day",
  "difficulty": 2,
  "priority": "high",
  "dueDate": "2026-12-31"
}
''';

      final reply = await testService.processChat(
        'Remind me to feed the cresties',
      );

      expect(reply, contains('I have added the task "Feed cresties"'));
      expect(mockSheet.addedChores.length, 1);
      expect(mockSheet.addedChores.first.taskName, 'Feed cresties');
    });

    test('Correctly parses natural language remove task to JSON', () async {
      testService.mockResponse = '''
{
  "action": "removeChore",
  "taskName": "Feed cresties"
}
''';

      final reply = await testService.processChat(
        'Cancel my geckos feeding chore',
      );

      expect(reply, contains('I have removed the task "Feed cresties"'));
      expect(mockSheet.removedChores.length, 1);
      expect(mockSheet.removedChores.first, 'Feed cresties');
    });

    test(
      'Gracefully falls back to chat message if not choosing tool action',
      () async {
        testService.mockResponse =
            'Hello! How can I help you keep track of things today?';

        final reply = await testService.processChat('Hi, robot');

        expect(
          reply,
          equals('Hello! How can I help you keep track of things today?'),
        );
        expect(mockSheet.addedChores.isEmpty, true);
      },
    );

    test('Correctly parses natural language complete task to JSON', () async {
      mockSheet.chores.add(
        ChoreTask(
          id: '123',
          taskName: 'Call deck contractor',
          description: 'Call them',
          dueDate: DateTime.now(),
          difficulty: 1,
          priority: 'high',
        ),
      );

      testService.mockResponse = '''
{
  "action": "completeChore",
  "taskName": "Call deck contractor"
}
''';

      final reply = await testService.processChat(
        'I\'ve called the deck contractor',
      );

      expect(
        reply,
        contains('I have marked the task "Call deck contractor" as completed!'),
      );
    });

    test('Intercepts multiple deletions without confirm keyword', () async {
      testService.mockResponse = '''
[
  {
    "action": "removeChore",
    "taskName": "Task 1"
  },
  {
    "action": "removeChore",
    "taskName": "Task 2"
  }
]
''';

      final reply = await testService.processChat('Wipe everything');

      expect(reply, contains('I detected a request to remove multiple tasks'));
      expect(mockSheet.removedChores.isEmpty, true); // Aborted!
    });
  });
}
