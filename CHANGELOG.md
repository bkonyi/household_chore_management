## 1.1.0

- Refactored `processChat` and `syncWithGoogleTasks` in `flows.dart` to reduce nesting and improve readability.
- Added validation to prevent adding tasks with past due dates.
- Enforced strict type safety by removing many instances of `dynamic`.
- Added Scenario E to `test_agent.dart` to verify past date validation.
- Cleaned up boilerplate files (`household_chore_management.dart`, `household_chore_management_test.dart`).

## 1.0.0

- Initial version.
