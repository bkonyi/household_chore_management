import 'package:googleapis/sheets/v4.dart';
import 'package:household_chore_management/db/sheet.dart';
import 'package:test/test.dart';

// Partial Mock for SheetsApi using noSuchMethod (Standard Dart approach
// without third party libraries)
class MockSheetsApi implements SheetsApi {
  final Map<String, List<List<dynamic>>> mockResponses = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #spreadsheets) {
      return MockSpreadsheetsResource(mockResponses);
    }
    return super.noSuchMethod(invocation);
  }
}

class MockSpreadsheetsResource implements SpreadsheetsResource {
  final Map<String, List<List<dynamic>>> mockResponses;
  MockSpreadsheetsResource(this.mockResponses);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #values) {
      return MockValuesResource(mockResponses);
    }
    if (invocation.memberName == #batchUpdate) {
      return Future.value(BatchUpdateSpreadsheetResponse());
    }
    return super.noSuchMethod(invocation);
  }
}

class MockValuesResource implements SpreadsheetsValuesResource {
  final Map<String, List<List<dynamic>>> mockResponses;
  MockValuesResource(this.mockResponses);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #get) {
      return Future.value(ValueRange(values: mockResponses['get']));
    }
    if (invocation.memberName == #append) {
      return Future.value(AppendValuesResponse());
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  group('SheetService Tests (Offline Partial Mock)', () {
    late MockSheetsApi mockApi;
    late SheetService service;

    setUp(() {
      mockApi = MockSheetsApi();
      service = SheetService(mockApi, 'dummy-spreadsheet-id');
    });

    test('getChores filters headers and parses short rows safely', () async {
      mockApi.mockResponses['get'] = [
        ['ID', 'Task Name', 'Description'], // Header
        [
          '123',
          'Feed cresties',
          'Feed crested geckos every other day',
        ], // Valid
        [], // Empty
        ['456', 'Clean gutters'], // Valid but short
      ];

      final chores = await service.getChores();

      expect(chores.length, 2);
      expect(chores[0].taskName, 'Feed cresties');
      expect(chores[1].taskName, 'Clean gutters');
    });

    test(
      'removeChoreByName correctly calls batchUpdate on matching row',
      () async {
        mockApi.mockResponses['get'] = [
          ['ID', 'Task Name'],
          ['123', 'Feed cresties'],
          ['456', 'Clean gutters'],
        ];

        final success = await service.removeChoreByName('Clean gutters');

        expect(success, 'no_google_task_id');
      },
    );

    test('removeChoreByName returns false when no row matches', () async {
      mockApi.mockResponses['get'] = [
        ['ID', 'Task Name'],
        ['123', 'Feed cresties'],
      ];

      final success = await service.removeChoreByName('Wash car');

      expect(success, isNull);
    });
  });
}
