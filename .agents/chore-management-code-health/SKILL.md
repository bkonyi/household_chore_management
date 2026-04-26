---
name: Chore Management Code Health
description: Rules for maintaining code quality, analysis, and formatting in the project.
---
# Chore Management Code Health

This skill outlines the mandatory practices for maintaining code quality in the `household_chore_management` project.

## Rules
1.  **Static Analysis**: Whenever making changes, be sure to run `dart analyze` and fix all errors, warnings, and lints. Never commit code with unresolved analysis issues.
2.  **Code Formatting**: `dart format` should also be run before committing to ensure a consistent style across the project.
