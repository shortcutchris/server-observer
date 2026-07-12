# Server Observer delivery rules

These repository-local rules apply to every future coding task.

## Validation

- Build every source or configuration change with the `ServerObserver` scheme for macOS.
- Run the complete `ServerObserver` test suite before declaring a change complete.
- For user-interface changes, also verify the affected interaction in a runnable build whenever local UI control is available.
- Report the exact validation result, including the number of passing tests.

## Documentation

- Keep `CHANGELOG.md` current for every release.
- Add version-specific notes under `release-notes/<version>.md` for every release.
- Update `README.md`, `SPEC.md`, or configuration examples whenever behavior, setup, or user-facing capabilities change materially.

## Delivery

- When the user requests deployment, publication, or complete delivery, treat the following as one workflow: version bump, release notes, build, tests, focused commit, pull request, successful CI, merge, version tag, signed and notarized GitHub release, Sparkle appcast update, local installation, and launch verification.
- Use the next appropriate semantic version and increment `CURRENT_PROJECT_VERSION`.
- Verify the GitHub release assets and the appcast after publishing.
- Do not publish an external release for exploratory work, reviews, or local-only requests unless the user asks for delivery.
