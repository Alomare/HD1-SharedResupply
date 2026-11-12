# Rules for this repository

**Every release has a changelog.** Before tagging, add a section for the version to `CHANGELOG.md`, headed `## <version>`, listing the new, changed or removed features. Each change is one list item, starting `- New:`, `- Changed:` or `- Removed:`, and describes the change briefly and directly. The Release workflow publishes that section as the release notes on GitHub (the Nexus upload carries no changelog), and stops if the section is missing or `python tools/nexus_release.py check` rejects the wording.
