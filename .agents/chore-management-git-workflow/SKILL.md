---
name: Chore Management Git Workflow
description: Rules for git operations in the project.
---
# Chore Management Git Workflow

This skill outlines the mandatory git practices for the `household_chore_management` project.

## Rule
Whenever a feature has been added and tested, it **must** be pushed to GitHub to keep the remote repository in sync with the latest work.

### Best Practices:
- Verify that `dart analyze` passes without errors or warnings before pushing.
- Verify that all unit and integration tests pass before pushing.
- Use descriptive commit messages explaining what was added or fixed.

## CRITICAL SECURITY RULE
- **NEVER** push any sort of private information to GitHub, including credentials, OAuth tokens, or Discord bot tokens.
- Ensure files containing secrets (like `.env`, `credentials.json`, `tokens.json`) are added to `.gitignore` or managed securely.
