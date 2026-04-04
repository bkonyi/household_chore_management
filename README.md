# Household Chore Management

A Discord bot powered by Genkit and Gemini to manage household chores, synced with Google Sheets and Google Tasks.

## Features

- **Natural Language Interaction**: Chat with the bot in Discord to manage chores.
- **Add Chores**: Add tasks with optional descriptions, difficulty, priority, and due dates.
- **Remove Chores**: Delete tasks by name.
- **Complete Chores**: Mark tasks as completed.
- **Sync with Google Tasks**: Bi-directional sync between Google Sheets and Google Tasks.
- **Past Date Validation**: Prevents adding tasks with due dates in the past.

## Tech Stack

- **Core**: Dart
- **AI**: Genkit, Gemini (`gemini-2.5-flash`)
- **Integration**: Discord (Nyxx library)
- **Database**: Google Sheets (via `googleapis`)
- **Task Management**: Google Tasks (via `googleapis`)

## Setup

1.  **Environment Variables**: Create a `.env` file in the root directory (see `.env.template`) and fill in:
    - `DISCORD_TOKEN`: Your Discord bot token.
    - `GOOGLE_SHEET_ID`: The ID of the Google Sheet used as a database.
    - `GEMINI_API_KEY`: Your Gemini API key.
    - `TASK_LIST_ID`: The ID of the Google Tasks list (defaults to `@default`).

2.  **Credentials**: Place your Google API `credentials.json` in the root directory. On first run, it will guide you through OAuth flow to generate `tokens.json`.

## Running the Bot

To start the bot, run:

```bash
dart bin/household_chore_management.dart
```

## Running Tests

### Unit Tests
```bash
dart test
```

### Integration Tests
To run live integration tests (requires bot running in background):
```bash
dart bin/test_agent.dart
```
