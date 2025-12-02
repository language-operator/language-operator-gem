Time to release a new version!

1. Update the patch version in lib/language_operator/version.rb and re-run bundler to update the lockfile.
2. Update the agent image in components/agent/Gemfile as well, and again ensuring the lockfile is updated.
3. Commit the version with the message "vX.Y.Z" and push to origin.
4. Tag the new version and push to origin with the --tags argument.
