# Chore Agent Tasks

- `[x]` Initialize Dart Project and Dependencies
- `[x]` Create Docker and Setup Environment Variables
- `[x]` Implement Google Sheets Integration (`lib/db/sheet.dart`)
- `[x]` Implement Google Tasks Integration (`lib/db/tasks.dart`)
- `[x]` Define GenKit Flows and Tools (`lib/genkit/`)
- `[x]` Implement Discord Bot with `nyxx` (`lib/bot/bot.dart`)
- `[x]` Verification & Testing

## Auth Switch Tasks

- `[x]` Update Authentication to OAuth 2.0 (Write JSON and update Dart code)
- `[x]` Update docker-compose.yml to mount tokens.json

## Natural Chat Tasks

- `[x]` Define `processChat` in `lib/genkit/flows.dart` (Inject SheetService)
- `[x]` Update `DiscordBot` to use `processChat` for non-commands
- `[x]` Update `bin/household_chore_management.dart` to inject SheetService

## Remove Chores Tasks

- `[/]` Implement `removeChoreByName` in `lib/db/sheet.dart` using batchUpdate
- `[ ]` Update `processChat` prompt and handling in `lib/genkit/flows.dart` to support removeChore action
