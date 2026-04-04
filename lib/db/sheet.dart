import 'package:googleapis/sheets/v4.dart';

/// Represents a household chore task.
class ChoreTask {
  /// Unique identifier for the task.
  final String id;

  /// The name of the task.
  final String taskName;

  /// Detailed description of the task.
  final String description;

  /// Optional due date for the task.
  final DateTime? dueDate;

  /// Difficulty level of the task (1-5).
  final int difficulty; // 1-5

  /// Priority level of the task.
  final String priority; // P1, P2, P3

  /// Optional rule for recurring tasks.
  final String? recurrenceRule;

  /// Timestamp of when the task was last completed.
  final DateTime? lastCompletedAt;

  /// Optional identifier for the linked Google Task.
  final String? googleTaskId;

  /// Creates a [ChoreTask].
  ChoreTask({
    required this.id,
    required this.taskName,
    required this.description,
    this.dueDate,
    required this.difficulty,
    required this.priority,
    this.recurrenceRule,
    this.lastCompletedAt,
    this.googleTaskId,
  });

  factory ChoreTask.fromRow(List<Object?> row) {
    final id = row.isNotEmpty
        ? row[0].toString()
        : DateTime.now().millisecondsSinceEpoch.toString();
    final name = row.length > 1 ? row[1].toString() : 'Unnamed Chore';
    final desc = row.length > 2 ? row[2].toString() : '';
    final date = row.length > 3 && row[3].toString().isNotEmpty
        ? DateTime.tryParse(row[3].toString())
        : null;
    final difficulty = row.length > 4
        ? int.tryParse(row[4].toString()) ?? 3
        : 3;
    final priority = row.length > 5 ? row[5].toString() : 'medium';

    return ChoreTask(
      id: id,
      taskName: name,
      description: desc,
      dueDate: date,
      difficulty: difficulty,
      priority: priority,
      recurrenceRule: row.length > 6 ? row[6]?.toString() : null,
      lastCompletedAt: row.length > 7 && row[7] != null
          ? DateTime.tryParse(row[7].toString())
          : null,
      googleTaskId: row.length > 8 ? row[8]?.toString() : null,
    );
  }

  List<Object?> toRow() {
    return [
      id,
      taskName,
      description,
      dueDate?.toUtc().toIso8601String() ?? '',
      difficulty,
      priority,
      recurrenceRule,
      lastCompletedAt?.toUtc().toIso8601String(),
      googleTaskId,
    ];
  }
}

/// Abstract interface for interacting with the chore database.
abstract class ChoreDatabase {
  /// Retrieves all chores from the database.
  Future<List<ChoreTask>> getChores();

  /// Adds a new [task] to the database.
  Future<void> addChore(ChoreTask task);

  /// Removes a chore by its [taskName].
  /// Returns the Google Task ID if it was linked, or null.
  Future<String?> removeChoreByName(String taskName);

  /// Updates an existing [task] in the database.
  Future<void> updateChore(ChoreTask task);
}

/// Implementation of [ChoreDatabase] that uses Google Sheets as the storage.
class SheetService implements ChoreDatabase {
  /// The Google Sheets API client.
  final SheetsApi sheetsApi;

  /// The ID of the Google Sheet used for storage.
  final String spreadsheetId;

  /// Creates a [SheetService] with the required [sheetsApi] and
  /// [spreadsheetId].
  SheetService(this.sheetsApi, this.spreadsheetId);

  @override
  Future<List<ChoreTask>> getChores() async {
    final response = await sheetsApi.spreadsheets.values.get(
      spreadsheetId,
      'A1:I', // Read from the first row
    );
    final rows = response.values;
    if (rows == null || rows.isEmpty) return [];

    // Filter out empty rows and skip the header row if present
    final validRows = rows.where(
      (row) =>
          row.isNotEmpty &&
          row[0].toString().trim().isNotEmpty &&
          row[0].toString().toLowerCase() != 'id' &&
          row[0].toString().toLowerCase() != 'task id' &&
          (row.length <= 7 ||
              row[7] == null ||
              row[7].toString().trim().isEmpty),
    );

    return validRows.map(ChoreTask.fromRow).toList();
  }

  @override
  Future<void> addChore(ChoreTask task) async {
    final checkResponse = await sheetsApi.spreadsheets.values.get(
      spreadsheetId,
      'A1:A1',
    );
    final existingRows = checkResponse.values;
    if (existingRows == null || existingRows.isEmpty) {
      final headers = [
        'ID',
        'Task Name',
        'Description',
        'Due Date',
        'Difficulty',
        'Priority',
        'Recurrence',
        'Last Completed At',
        'Google Task ID',
      ];
      await sheetsApi.spreadsheets.values.update(
        ValueRange(values: [headers]),
        spreadsheetId,
        'A1:I1',
        valueInputOption: 'USER_ENTERED',
      );
    }

    await sheetsApi.spreadsheets.values.append(
      ValueRange(values: [task.toRow()]),
      spreadsheetId,
      'A1',
      valueInputOption: 'USER_ENTERED',
    );
  }

  @override
  Future<void> updateChore(ChoreTask task) async {
    final response = await sheetsApi.spreadsheets.values.get(
      spreadsheetId,
      'A1:I', // Read all rows to find the exact zero-based index
    );
    final rows = response.values;
    if (rows == null || rows.isEmpty) throw Exception('Database is empty');

    final index = rows.indexWhere(
      (r) => r.isNotEmpty && r[0].toString() == task.id,
    );
    if (index == -1) throw Exception('Task with ID ${task.id} not found');

    final rowIndex = index + 1; // 1-indexed for sheets
    await sheetsApi.spreadsheets.values.update(
      ValueRange(values: [task.toRow()]),
      spreadsheetId,
      'A$rowIndex:I$rowIndex',
      valueInputOption: 'USER_ENTERED',
    );
  }

  @override
  Future<String?> removeChoreByName(String taskName) async {
    final response = await sheetsApi.spreadsheets.values.get(
      spreadsheetId,
      'A1:I', // Read all rows to find the exact zero-based index
    );
    final rows = response.values;
    if (rows == null || rows.isEmpty) return null;

    // Find the row index in the original list (0-based)
    final index = rows.indexWhere(
      (r) =>
          (r.length > 1 &&
              r[1].toString().toLowerCase().contains(taskName.toLowerCase())) ||
          (r.isNotEmpty &&
              r[0].toString().toLowerCase().contains(taskName.toLowerCase())),
    );
    if (index == -1) return null;

    final row = rows[index];
    final googleTaskId = row.length > 8 ? row[8]?.toString() : null;

    final startIndex = index; // index 0 means row 1
    final endIndex = index + 1; // exclusive

    final batchUpdateRequest = BatchUpdateSpreadsheetRequest(
      requests: [
        Request(
          deleteDimension: DeleteDimensionRequest(
            range: DimensionRange(
              sheetId: 0, // Assuming first sheet (gid=0)
              dimension: 'ROWS',
              startIndex: startIndex,
              endIndex: endIndex,
            ),
          ),
        ),
      ],
    );

    await sheetsApi.spreadsheets.batchUpdate(batchUpdateRequest, spreadsheetId);
    return googleTaskId ?? 'no_google_task_id';
  }
}
