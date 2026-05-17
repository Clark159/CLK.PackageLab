# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CLK.PackageLab is a Maven package management utility written in PowerShell. It resolves and downloads Maven dependencies (including transitive ones) into a local `Maven/packages/` directory using a two-step workflow.

**Prerequisites:** PowerShell 5.1+, Maven (`mvn` on PATH), internet access to Maven Central and Google Maven.

## Commands

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

Steps must be run in order. There are no lint or test commands — the scripts include built-in validation (exit code checks, file existence checks, download verification).

## Architecture

### Two-Step Workflow

```
packages.txt  →  [maven-resolve-packages]  →  pom.xml
                                            →  packages-lock.txt
                                            →  packages-lock.xml (BOM)
                                            →  packages-new.txt

packages-lock.*  →  [maven-fetch-packages]  →  Maven/packages/*.jar
```

### Key Files

| File | Role |
|------|------|
| `Maven/packages.txt` | Input: one `groupId:artifactId:version` per line |
| `Maven/pom.xml` | Generated Maven descriptor; parent points to `packages-lock.xml` |
| `Maven/packages-lock.txt` | Flat list of all resolved dependencies (including transitive) |
| `Maven/packages-lock.xml` | BOM (Bill of Materials) locking all dependency versions |
| `Maven/packages-new.txt` | Newly added/updated packages from last resolution run |
| `Maven/packages/` | Downloaded `.jar` files |

### Script Internals

**`maven-resolve-packages.ps1`** — Clears previous outputs, generates a temporary `settings.xml` pointing to Maven Central and Google Maven, runs `mvn dependency:list` to expand transitive dependencies, then builds `pom.xml` and `packages-lock.xml` using .NET XML DOM APIs.

**`maven-fetch-packages.ps1`** — Validates lock files exist, runs `mvn dependency:go-offline` then `mvn dependency:copy-dependencies`, verifies every expected `.jar` was downloaded, and cleans up the temporary `.m2` cache.

### Important Behaviors

- Both scripts **clear their outputs at the start** of each run (packages directory and `.m2` cache are deleted before downloading).
- The `packages-lock.xml` is wired as the parent POM so `pom.xml` inherits version management from it.
- Only `runtime` scope dependencies are included in the final package set.
- UTF-8 encoding is enforced throughout for cross-platform XML compatibility.
