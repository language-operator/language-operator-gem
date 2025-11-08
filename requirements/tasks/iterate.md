# Iterate

Background: this is a early-phase project that works exclusively in main, and each task is a patch release.

Follow these directions closely:

1. Use the ForgeJo tool to find the top issue for this repository.
2. Investigate if it's valid, or a mis-use of the intended feature.
3. Plan your course of action and propose it before making changes.
4. Add your implementation plan as a comment on the issue.
5. Implement the changes.
6. Run existing tests, and add new ones if necessary.
7. **CRITICAL: Test the actual functionality manually before committing.** If it's a CLI command, run it. If it's library code, test it in the appropriate context. Never commit untested code.
8. Commit the change and push to origin.
9. When the user *confirms* CI passes, update the patch version in lib/language_operator/version.rb
10. Commit the version with the message "vX.Y.Z" and push to origin.
11. Tag the new version and push to origin with the --tags argument.
12. Comment on your solution in the ForgeJo issue.
13. Resolve the issue.
