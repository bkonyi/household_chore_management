---
name: Chore Management Testing Practices
description: Rules for adding tests when implementing new features in the household_chore_management project.
---
# Chore Management Testing Practices

This skill outlines the mandatory testing practices for the `household_chore_management` project.

## Core Rule
Whenever a new feature is added to this project, it **must** always have tests added to verify its functionality.

### Requirements:
1.  **Unit Tests**: Cover individual functions, classes, and isolated logic (e.g., calculating dates, parsing JSON).
2.  **Integration Tests**: Verify that components work together correctly (e.g., bot interacting with GenKit, or database syncing with Google Tasks).

## Best Practices
- Check existing tests in `test/` directory for patterns (e.g., [bot_test.dart](file:///Users/bkonyi/household_chore_management/test/bot_test.dart)).
- Use mocking for external services like Gemini or Google APIs to keep tests offline and fast.
- Verify your code passes analysis after each change before committing or pushing.
