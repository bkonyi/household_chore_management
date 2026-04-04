# Chore & Task Management Agent (Dart + GenKit)

An agent that tracks and manages household chores using a Google Sheet as a database, syncs with Google Tasks for personal views, and communicates through Discord for alerts and interaction. Now using **Dart** and **GenKit** for agentic capabilities.

## Proposed Architecture

- **Runtime**: Dart 3.x
- **Framework**:
  - `package:genkit` for workflows and tool calling (AI behaviors).
  - `package:nyxx` for Discord bot interface.
  - `package:googleapis` (Sheets, Tasks) for data sync.
- **Containerization**: Docker

### Google Sheet Schema

A new sheet will be defined with the following columns:
- `ID` (Unique Identifier)
- `TaskName` (String)
- `Description` (String)
- `DueDate` (Date)
- `Difficulty` (1-5 representing 1=Minimal Energy to 5=High Energy)
- `Priority` (P1, P2, P3)
- `RecurrenceRule` (e.g., `daily`, `weekly`, `monthly`, `every X days`, `none`)
- `LastCompletedAt` (Date)
- `GoogleTaskId` (String, for sync)

### Discord Interaction Model (Powered by GenKit)

GenKit will serve as the brain of the agent. When a user sends a message or invokes a command, GenKit can use **Tools** to interact with Google Sheets or Tasks, and generate a friendly, professional response.

- **Reminders**: Periodic messages (via cron/timers) about upcoming tasks.
- **Slash Commands** or **Natural Language Interactivity** (GenKit can handle both):
  - Natural: "I have 30 minutes and low energy. What can I do?" -> GenKit calls `searchChoresTool` -> Generates friendly response.
  - Commands: `/suggest [energy] [time]`, `/list`, `/complete [id]`, `/snooze [id] [days]`.

---

## User Review Required

> [!IMPORTANT]
> **Google OAuth Credentials Required**: To sync with your personal Google Tasks, we need an OAuth client secret JSON. Since standard service accounts do not see your personal tasks.
> You will need to place `credentials.json` in a specific directory or use env vars.

> [!WARNING]
> **Google Tasks API Limitations**: The API does not natively support "recurring tasks". We will implement the recurrence logic in our agent in Dart (the agent will calculate the next date and create a new instance when one is completed).

---

## Proposed Changes

### [Component] Database & Sheets Sync

#### [NEW] `lib/db/sheet.dart`
Interactions with Google Sheet to read/write task definitions.

#### [NEW] `lib/db/tasks.dart`
Interactions with Google Tasks API to create/delete/update tasks.

### [Component] GenKit Features

#### [NEW] `lib/genkit/flows.dart`
Definition of GenKit flows (e.g., `suggestChoresFlow`, `handleRemindersFlow`).

#### [NEW] `lib/genkit/tools.dart`
Tools exposed to GenKit (e.g., `getChoresFromSheet`, `updateTaskStatus`).

### [Component] Discord Bot Interface

#### [NEW] `lib/bot/bot.dart`
Main entry point for Discord bot using `nyxx`. Dispatches events to GenKit flows.

### [Component] Infrastructure

#### [NEW] `Dockerfile`
Standard Dart run dynamic environment.

#### [NEW] `pubspec.yaml`
Dependencies for `nyxx`, `genkit`, `googleapis`.

---

## Open Questions

None at this time. We are assuming standard Dart VM stack and user-supplied OAuth `credentials.json`.

---

## Verification Plan

### Automated Tests
- Unit tests for:
  - Task recurrence calculations.
  - Suggestion algorithm (matching difficulty to energy).

### Manual Verification
- Testing bot commands in a private Discord test server.
- Verifying Sheet updates and Google Tasks creation manually.
- Simulating a cron trigger for reminders.
