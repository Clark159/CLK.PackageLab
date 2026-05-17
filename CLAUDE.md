# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CLK.PackageLab is a Maven package management utility written in PowerShell. It resolves and downloads Maven dependencies (including transitive ones) into a local `Maven/packages/` directory using a two-step workflow.

**Prerequisites:** PowerShell 5.1+, Maven (`mvn` on PATH), internet access to Maven Central and Google Maven.

## Commands

### Maven

**Step 1 — Resolve dependencies** (reads `packages.txt`, generates lock files):
```powershell
.\Maven\maven-resolve-packages.ps1
# or
.\Maven\maven-resolve-packages.bat
```

**Step 2 — Download packages** (reads lock files, populates `Maven/packages/`):
```powershell
.\Maven\maven-fetch-packages.ps1
# or
.\Maven\maven-fetch-packages.bat
```

### npm

**Step 1 — Resolve dependencies** (reads `packages.txt`, generates lock files for both linux-x64 and win32-x64):
```powershell
.\Npm\npm-resolve-packages.ps1
# or
.\Npm\npm-resolve-packages.bat
```

**Step 2 — Download packages** (reads `packages-lock.txt`, downloads `.tgz` tarballs into `Npm/packages/`):
```powershell
.\Npm\npm-fetch-packages.ps1
# or
.\Npm\npm-fetch-packages.bat
```

Steps must be run in order. There are no lint or test commands — the scripts include built-in validation (exit code checks, file existence checks, download verification).

Both scripts in each tool accept a `-Pause` switch (automatically passed by the `.bat` launchers) to wait for a keypress before exit.

## Architecture

### Two-Step Workflow

**Maven:**
```
Maven/packages.txt  →  [maven-resolve-packages]  →  Maven/pom.xml
                                                  →  Maven/packages-lock.txt
                                                  →  Maven/packages-lock.xml (BOM)
                                                  →  Maven/packages-new.txt

Maven/packages-lock.*  →  [maven-fetch-packages]  →  Maven/packages/<group>/<artifact>/<version>/
```

**npm:**
```
Npm/packages.txt  →  [npm-resolve-packages]  →  Npm/package.json
                       (linux-x64 + win32-x64)  →  Npm/packages-lock.txt  (merged)
                                                 →  Npm/packages-new.txt

Npm/packages-lock.txt  →  [npm-fetch-packages]  →  Npm/packages/<name>-<version>.tgz
```

### Maven Key Files

| File | Role |
|------|------|
| `Maven/packages.txt` | Input: one `groupId:artifactId:version` per line |
| `Maven/pom.xml` | Generated Maven descriptor; parent points to `packages-lock.xml` |
| `Maven/packages-lock.txt` | Flat list of resolved dependencies as `groupId:artifactId:version` |
| `Maven/packages-lock.xml` | BOM (Bill of Materials) locking all dependency versions |
| `Maven/packages-new.txt` | Packages that returned 404 when HEAD-checked against `$mavenRepositoryUrl` |
| `Maven/packages/` | Downloaded artifacts in full Maven directory structure |

### npm Key Files

| File | Role |
|------|------|
| `Npm/packages.txt` | Input: one `name:version` per line (supports `#` comments) |
| `Npm/package.json` | Generated npm descriptor listing direct dependencies |
| `Npm/packages-lock.txt` | Flat merged list of all resolved dependencies as `name:version` |
| `Npm/packages-new.txt` | Packages that returned 404 when HEAD-checked against `$npmRegistryUrl` |
| `Npm/packages/` | Downloaded `.tgz` tarballs (flat, named `<name>-<version>.tgz`) |

### Maven Script Internals

**`maven-resolve-packages.ps1`**

1. Clears previous outputs (`.m2`, `packages/`, lock files, generated XMLs).
2. Builds `pom.xml` from `packages.txt` via string construction, then generates a temporary `settings.xml` pointing to Maven Central and Google Maven.
3. Runs `mvn dependency:list` to expand transitive dependencies; parses its `groupId:artifactId:type:version[:scope]` output into `packages-lock.txt` (format: `groupId:artifactId:version`).
4. Builds `packages-lock.xml` (BOM with `<dependencyManagement>`) via string construction.
5. Uses .NET `XmlDocument` API to insert a `<parent>` reference to `packages-lock.xml` into the already-written `pom.xml`.
6. Builds `packages-new.txt` by HEAD-requesting each resolved dependency at `$mavenRepositoryUrl`; lists only packages that returned 404.

**`maven-fetch-packages.ps1`**

Two-phase download using a local `.m2` cache at `Maven/.m2` (not the user's global cache):

1. **Phase 1** — Writes `settings.xml` with all repos (`mavenSourceList`: Maven Central + Google Maven) and runs `mvn dependency:go-offline` to populate `.m2`.
2. **Phase 2** — Rewrites `settings.xml` pointing only to `$mavenSourceProxyUrl`, deletes the target packages from `.m2`, then runs `mvn dependency:resolve` to re-fetch them from the proxy URL only.
3. Copies each resolved artifact from `.m2` into `packages/` preserving the Maven directory structure (`groupId-path/artifactId/version/`). Missing packages are reported as errors.
4. Cleans up `.m2` and `settings.xml`.

### npm Script Internals

**`npm-resolve-packages.ps1`**

1. Clears previous outputs (`node_modules`, `packages/`, lock files).
2. Builds `package.json` from `packages.txt` via string construction.
3. For each platform in `$platformList` (linux-x64, win32-x64): sets `$env:npm_config_platform` and `$env:npm_config_arch`, then runs `npm install --package-lock-only --ignore-scripts` to resolve that platform's dependency tree (no `node_modules` created).
4. Parses each `package-lock.json` — handles nested `node_modules/a/node_modules/b` paths by taking the last segment after `node_modules/` — and merges all unique `name:version` pairs into a sorted set.
5. Writes merged `packages-lock.txt`. Restores env vars.
6. Generates `packages-new.txt` by HEAD-checking each resolved package's tarball URL at `$npmRegistryUrl`; lists packages that returned 404.

**`npm-fetch-packages.ps1`**

1. Validates `package.json` and `packages-lock.txt` exist; clears `packages/`.
2. For each `name:version` in `packages-lock.txt`, runs `npm pack <name>@<version> --pack-destination ./packages` to download the `.tgz` tarball.
3. Verifies each expected tarball exists (filename: `<name-without-@scope>-<version>.tgz`); reports any missing as errors.

### Important Behaviors

- Both scripts **clear their outputs at the start** of each run (packages directory and `.m2` cache are deleted before downloading).
- Both scripts use a `do { ... } while ($false)` loop as a structured early-exit mechanism instead of exceptions; `$exitCode` carries the result.
- The `packages-lock.xml` is wired as the parent POM so `pom.xml` inherits version management from it.
- `settings.xml` is generated at runtime and deleted at completion — it is not a permanent config file.
- UTF-8 encoding is enforced throughout for cross-platform XML compatibility.
