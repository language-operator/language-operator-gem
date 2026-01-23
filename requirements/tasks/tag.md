Time to release a new version!

1. Update the patch version in lib/language_operator/version.rb and re-run bundler to update the lockfile.
2. Commit the version with the message "vX.Y.Z".
3. Tag the new version and push to origin with the --tags argument.
4. When CI completes, update the agent image in components/agent/Gemfile, rebuild its lockfile, and push to origin.