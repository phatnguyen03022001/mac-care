# Mac Maintenance Safety Policy

## Purpose

This policy governs any ChatGPT, Executor, coding agent, or authorized local execution surface performing Mac investigation, system-health diagnosis, storage analysis, junk cleanup, unused-application analysis, Homebrew maintenance, developer-environment cleanup, or CPU/RAM/process investigation.

**INSPECTION AUTHORITY != DELETION AUTHORITY.**

Local shell or MCP access is execution capability, not permission to inspect arbitrary private user data or perform destructive mutation. All cleanup and investigation authority is bounded by this policy.

## Required execution model

Every maintenance task follows:

`SCAN → CLASSIFY → PROPOSE → APPROVE when required → EXECUTE → VERIFY`

Every cleanup candidate is exactly one of:

- **SAFE** — clearly regenerable or disposable. Automatic cleanup is allowed only when the current task authorizes cleanup and the exact target, ownership, category, symlink resolution, and deletion boundary have been verified.
- **REVIEW** — potentially useful, user-significant, shared, or uncertain. Explicit operator approval is required before destructive mutation.
- **PROTECTED** — outside cleanup authority. It must not be read for cleanup purposes or deleted. There is no implicit override.

When uncertain between categories, choose the safer category.

## Investigation rules

Agents may inspect non-sensitive metadata materially required for maintenance, including:

- filesystem capacity and free space;
- aggregate directory sizes for allowed roots;
- CPU utilization, RAM usage, memory pressure, and swap usage;
- process PID, process/application name, CPU, RSS/memory, uptime, and parent/child relation when required;
- application bundle metadata, installed size, and last-used signals where available;
- Homebrew package metadata, outdated items, cleanup candidates, cache information, and health;
- developer caches, build artifacts, known regenerable caches, appropriate logs/temp files;
- aggregate Docker/OrbStack disk usage.

Prefer metadata, aggregate sizes, and bounded listings over file-content reads. Do not recursively crawl the entire home directory merely to find cleanup candidates.

## Absolute Photos protection

Photos are **PROTECTED** and absolutely outside agent authority.

Agents must not read, enumerate contents, search, index, inspect, hash, copy, modify, delete, or derive content from:

- `~/Pictures/**`;
- any path matching or resolving into `**/*.photoslibrary/**`;
- `~/Library/Photos/**`;
- `~/Library/Containers/com.apple.Photos*`;
- Photos-related Group Containers.

A `.photoslibrary` package anywhere on any mounted volume is PROTECTED regardless of where the operator moved it. Reject it before traversal.

Do not automate Photos.app or use AppleScript/JXA against Photos. Do not inspect Photos databases, thumbnails, internal metadata, Hidden album content, or Recently Deleted content. The operator’s private and hidden photos are outside agent authority.

## Credentials and secrets

Agents must not inspect credential or secret contents. Protected locations/classes include at minimum:

- `~/Library/Keychains/**` and `/Library/Keychains/**`;
- `~/.ssh/**`;
- `~/.gnupg/**`;
- `~/.aws/**`;
- `~/.kube/**`;
- `~/.config/gcloud/**`;
- `~/.npmrc`, `~/.pypirc`, and `~/.netrc`;
- Docker credential stores or configuration containing auth material;
- browser cookies, sessions, login databases, auth stores, token stores, and credential databases;
- password-manager databases, vaults, exports, and local credential stores.

Do not run credential-extraction operations such as `security dump-keychain`, `security find-*-password`, password harvesting, token harvesting, cookie extraction, browser-session extraction, or password searching.

If a secret is encountered accidentally, do not print, copy, report, or continue reading it beyond what is required to stop safely.

## Environment and command privacy

Do not dump complete environment state. `env`, `printenv`, process-environment extraction, and equivalent bulk collection are forbidden by default.

A single known non-sensitive environment variable may be queried only when materially required for the current authorized task.

Do not collect full process argv by default because command-line arguments may contain secrets. Prefer PID, name, CPU, RSS/memory, uptime, and parent/child relation when required.

## Clipboard

Clipboard contents are private. Do not use `pbpaste` or equivalent clipboard-reading APIs unless the operator explicitly requests clipboard inspection in the current task.

## Personal data

Do not read user document contents merely to decide whether they are junk. Personal content is not cleanup material by default.

Documents, Desktop files, personal downloads, media, archives of unknown purpose, project source, databases, and personal application data are REVIEW or PROTECTED according to sensitivity and value. Aggregate size metadata may be reported where safe, but contents must not be opened merely for cleanup classification.

## SAFE cleanup

SAFE candidates may include well-understood regenerable state such as known caches, old temporary files, obsolete logs where safe, package-manager caches, Homebrew cleanup candidates, Xcode DerivedData, known build output, task-owned temporary artifacts, and clearly disposable repository-local build caches.

Before deleting SAFE data, verify:

- canonical target path;
- expected category and ownership;
- non-PROTECTED status;
- symlink resolution;
- exact deletion boundary;
- target is not a broad ancestor of unrelated or user state.

Never convert uncertainty into SAFE.

## REVIEW cleanup

Explicit operator approval is required before destructive mutation of items such as:

- unused applications or application leftovers;
- simulator/device data;
- large developer artifacts with plausible value;
- Downloads content;
- Application Support or application containers;
- old local projects;
- archives;
- unknown large directories;
- data belonging to removed applications;
- any state with plausible user value.

A last-used timestamp is evidence for a recommendation only. It is not deletion authority. Do not automatically uninstall applications.

## PROTECTED cleanup

Never clean Photos, credentials, tokens, browser authentication/session state, password-manager data, private/personal documents based only on cleanup heuristics, or unknown sensitive data.

PROTECTED has no automatic override.

## Homebrew

Agents may inspect installed formulae/casks, outdated items, unused dependencies, cleanup candidates, cache size, and Homebrew health. Prefer official Homebrew dry-run/read-only operations before mutation.

Homebrew cleanup may be performed when explicitly within the maintenance request and the exact Homebrew boundary is known. Do not automatically install, upgrade, uninstall, or otherwise change packages merely because they are outdated; those are separate mutations requiring current-task authority.

Homebrew inspection never justifies broad credential or environment inspection.

## Application analysis

Agents may inspect expected application roots such as `/Applications` and `~/Applications` using non-sensitive metadata: application name, bundle ID, version, size, and last-used signal where available.

Do not open application-private data merely to determine whether an app is unused. Uninstalling an application is REVIEW. Application leftovers are REVIEW unless positively established as entirely regenerable/disposable.

## Developer environment

The canonical local repository root is `/Users/tienphat/Developer/`.

Agents may inspect clearly regenerable developer state under that root, including build output, compiler caches, dependency caches, DerivedData, and task-owned temporary directories.

Repository source and local work are not junk. Before deleting repository-associated state, verify as materially applicable:

- actual Git repository identity;
- remote identity;
- working-tree status;
- whether the data is generated/reproducible;
- whether local uncommitted work exists.

Never use `git clean`, hard reset, recursive repository deletion, or overwrite a repository merely for machine cleanup without explicit authority.

## Package managers and local tooling

Normal macOS tooling may use its standard locations, including Homebrew, npm, pnpm, yarn, Go, and Swift. Do not relocate or sandbox normal package-manager state merely for cleanup.

Installing, upgrading, or removing packages is a separate mutation from cleanup and requires appropriate current-task authority.

## Path and symlink safety

Before destructive filesystem mutation:

- canonicalize the target path;
- resolve symlinks safely;
- reject unresolved targets;
- reject filesystem root, user home root, and broad ancestors;
- reject PROTECTED targets and traversal into PROTECTED targets;
- establish the exact bounded deletion set.

A symlink from an allowed location into a PROTECTED location remains PROTECTED. Never follow a symlink merely because its textual source path appears safe.

## Shared infrastructure

Cleanup or investigation authority does not authorize lifecycle mutation of shared execution infrastructure.

Do not stop, restart, kill, signal, reconfigure, replace, or delete:

- Agent Runtime;
- Remote Desktop Commander;
- secure tunnels;
- port `8080` infrastructure;
- shared operator containers/services;
- execution transport ancestors.

Only a separate infrastructure-maintenance task explicitly authorizing that action can permit it. Resource consumption or port occupation is not ownership proof.

## Docker and OrbStack

Agents may inspect aggregate Docker/OrbStack resource usage.

Do not blindly prune all containers, images, or volumes; delete unknown volumes; stop unrelated containers; or remove shared images merely because they are large. Only positively task-owned or explicitly approved disposable state may be destroyed. Unknown Docker/OrbStack state is REVIEW.

## Destructive command safety

Never issue broad destructive commands based on fuzzy matching. Avoid patterns equivalent to unbounded `rm -rf`, `find -delete`, wildcard deletion across user data, or mass recursive cleanup without candidate classification.

Destructive operations must address an exact bounded target set already classified under this policy.

## Reporting before cleanup

For material cleanup, report the target/category, approximate reclaimable size when available, why it is considered junk/unused, its SAFE/REVIEW/PROTECTED classification, and the proposed operation.

For REVIEW, stop for explicit operator approval. Prefer aggregate/grouped reporting over dumping thousands of paths.

## Verification after cleanup

After mutation verify that:

- the intended target changed or was removed;
- unrelated state remains;
- expected space was reclaimed when measurable;
- PROTECTED boundaries were not crossed;
- task-owned temporary state was cleaned when applicable.

Do not claim cleanup success merely because a command exited zero.

## Default fail-closed rule

- When uncertain about privacy: **PROTECTED**.
- When uncertain about deletion safety: **DO NOT DELETE**.
- When a candidate may have user value: **REVIEW**.
- When metadata is sufficient: **DO NOT READ CONTENT**.
- When destructive authority is missing: **ASK BEFORE MUTATION**.

Local execution capability is never itself authorization.

## Process investigation

Allowed by default: PID, executable/application name, CPU, RSS/memory, uptime, and parent/child relationship when materially required.

Do not inspect process environment or arbitrary process memory. Do not collect complete argv unless it is specifically required for the authorized task and can be done without exposing sensitive data.

High resource usage is diagnostic evidence only; it does not grant authority to terminate, signal, restart, or otherwise mutate a process.

## Integration with existing Mac Care

`RULES.md` is the canonical human/agent policy authority for maintenance performed through Mac Care or any other explicitly authorized local execution surface.

Existing executable protections, including `PrivacyPolicy`, remain implementation-level defense and must not be weakened. Do not duplicate this policy throughout production source, change existing MCP semantics, or add arbitrary shell, file-read, or delete capabilities to implement this document.
