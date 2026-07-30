# Repository instructions

## Release history

Every published release must have an annotated Git tag so its exact source can
be recovered later for maintenance or a forked update.

- Create the tag only after the release commit contains the exact files and
  version that were shipped.
- Use `<package-name>-v<version>` for new tags in this multi-mod repository,
  for example `perfect-placement-v0.1.5-crashfix.1`.
- Do not move, replace, or reuse a published release tag.
- Verify the tag resolves to the intended release commit before publishing.
- Push the release commit and its tag to the remote as part of the release
  workflow.
- Run `Release/Test-Release.ps1` against the final archive and complete
  `Release/PRE_DEPLOY_CHECKLIST.md` before publishing.
- When making a maintenance update for an older release line, create the branch
  from its release tag rather than reconstructing the release from changelog
  notes or a newer commit.

Treat a release as incomplete until its annotated tag has been verified and
pushed.

## Release file formatting

- Keep each prose paragraph and list item on one physical line in every human-authored release text file, including changelogs, descriptions, readmes, and checklists.
- For public changelogs other than the Nexus version changelog, keep each entry on one physical line and at or below 255 characters.
- For the Nexus version changelog, keep the entire value at or below 255 characters total, including all lines and line breaks.
- Format Nexus version changelogs as plain newline-separated sentences with no headings, bullets, or leading hyphens.
- Use extra line breaks only for structural Markdown or BBCode, code blocks, tables, and intentionally preformatted layouts.
- Review release diffs for accidental hard-wrapped sentences before committing or publishing.
