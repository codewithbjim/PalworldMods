# PalworldMods repository memory

These instructions preserve established decisions and repeatable workflows for this repository. Follow them unless the user explicitly asks for a change.

## Identity and privacy

- Use `virtualbjörn` as the public mod author and Git commit name.
- Use `19782129+codewithbjim@users.noreply.github.com` for commits in this repository.
- Never put the author's real name or work email in source files, metadata, archives, documentation, commit messages, or commit metadata.
- Before publishing, scan both reachable Git history and release contents for unintended personal identifiers.
- The repository-local Git configuration uses `user.useConfigOnly=true`; preserve that protection.

## Development flow

1. Inspect `git status` first and preserve unrelated or uncommitted user work.
2. Keep configuration defaults in each mod's source tree and preserve its established structure.
3. Run the mod's tests when a compatible runtime is available.
4. Validate mod metadata, author identity, version, and enablement files before deployment.
5. Review the diff and scan source/release artifacts for personal identifiers before committing or publishing.
6. Keep fixtures and tests deterministic; do not use real player, guild, save, or object IDs.
7. After every edit that changes a mod's runtime payload, copy the updated runtime files to the local game directory and verify source/deployed hashes before considering the task complete. Do not leave deployment as an unperformed follow-up.

## Local game deployment

- Current modding development installation: `E:\Projects\Palworld`.
- Default development UE4SS Mods directory: `E:\Projects\Palworld\Pal\Binaries\Win64\ue4ss\Mods`.
- Current Steam/managed installation: `F:\SteamLibrary\steamapps\common\Palworld`.
- Use the development installation for routine runtime deployment unless the user explicitly requests the Steam/managed installation.
- Ensure Palworld is stopped before replacing deployed files.
- If the user explicitly requests a live debug copy while Palworld is running, copy the files as requested and tell them to use UE4SS **Restart All Mods** before testing.
- Do not deploy repository-only content such as `tests/`, `fixtures/`, or `README.md` unless specifically needed for diagnosis.
- Verify deployed files against the source after copying. Start the game only after verification; UE4SS loads the mod on the next launch.

## History cleanup flow

- Rewrite published history only after explicit user authorization because commit hashes and collaborator clones are affected.
- Protect dirty work first, rewrite from an isolated fresh clone with a temporary mirror backup, and verify every reachable ref before force-pushing.
- After a successful force push, independently clone from GitHub and scan file contents plus author/committer metadata.
- Repoint the working clone to rewritten `origin/main`, restore uncommitted work, then prune old reflogs/objects and remove temporary backups.
- Remind collaborators to reclone after any rewrite. GitHub-cached commit pages or pull-request refs may require GitHub Support to purge.

## Release history

Every published release must have an annotated Git tag so its exact source can be recovered later for maintenance or a forked update.

- Create the tag only after the release commit contains the exact files and version that were shipped.
- Use `<package-name>-v<version>` for new tags in this multi-mod repository, for example `perfect-placement-v0.1.5-crashfix.1`.
- Do not move, replace, or reuse a published release tag.
- Verify the tag resolves to the intended release commit before publishing.
- Push the release commit and its tag to the remote as part of the release workflow.
- Run `Release/Test-Release.ps1` against the final archive and complete `Release/PRE_DEPLOY_CHECKLIST.md` before publishing.
- When making a maintenance update for an older release line, create the branch from its release tag rather than reconstructing the release from changelog notes or a newer commit.

Treat a release as incomplete until its annotated tag has been verified and pushed.

## Release file formatting

- Keep each prose paragraph and list item on one physical line in every human-authored release text file, including changelogs, descriptions, readmes, and checklists.
- For public changelogs other than the Nexus version changelog, keep each entry on one physical line containing fewer than 255 characters.
- Use extra line breaks only for structural Markdown or BBCode, code blocks, tables, and intentionally preformatted layouts.
- Review release diffs for accidental hard-wrapped sentences before committing or publishing.

## Nexus changelog field

- Treat the Nexus file-version changelog as one plain-text value, even when it contains multiple lines.
- Keep the entire value at or below 255 characters total, including all lines and line breaks.
- Use plain newline-separated sentences with no headings, bullets, or leading hyphens.
- Keep the full release notes in `Release/CHANGELOG.md`; the Nexus value is a concise summary only.
- Count the entire value before deployment and reject it when it exceeds 255 characters.
