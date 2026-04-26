---
name: Chore Management Deployment
description: Rules for deploying new features to Fly.io in the project.
---
# Chore Management Deployment

This skill outlines the mandatory deployment practices for the `household_chore_management` project.

## Rule
Whenever a new feature has been successfully implemented and tested, it **must** be deployed to Fly.io to make it live in the active bot.

### Verification before Deployment:
1.  Ensure that all unit and integration tests pass.
2.  Ensure that `dart analyze` passes without any errors or warnings.

### Deployment Command:
Run the following command to build and release the new version:
```bash
fly deploy
```
