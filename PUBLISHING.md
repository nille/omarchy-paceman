# Publishing Checklist

Use this checklist before submitting or updating the plugin on
OmarchyPlugins.com.

## Repository

- [x] Public GitHub repository
- [x] Plugin files at the repository root
- [x] Default branch is `main`
- [x] MIT license
- [x] README with installation, usage, configuration, uninstall, and privacy
- [x] Root-level `preview.png`
- [x] No symlinks
- [x] No required install or uninstall script
- [x] No external runtime package dependencies

## Manifest

- [x] `schemaVersion` is `1`
- [x] Plugin ID uses the owner namespace: `nille.paceman`
- [x] Kind and entry point agree: `bar-widget` / `entryPoints.barWidget`
- [x] Entry point is a safe relative path that exists
- [x] Default bar section is valid
- [x] Version uses semantic versioning
- [x] Settings defaults and schema defaults agree

## Release Validation

Run from the repository root:

```bash
omarchy plugin validate .
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= \
  /usr/lib/qt6/bin/qmltestrunner -input tests/qml
tests/harness/run
git status --short
```

Then test a clean install:

```bash
omarchy plugin add https://github.com/nille/omarchy-paceman --enable
omarchy plugin remove nille.paceman
```

Confirm the removal prompt before running the final command on a workstation
where the plugin is in active use.

## Submission

Submit the repository URL:

```text
https://github.com/nille/omarchy-paceman
```

The submission must reference the repository root, not a subdirectory,
archive, release asset, or raw manifest URL.
