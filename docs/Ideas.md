# Ideas

## prplangit

**Repository Lifecycle Steward** - A daemon that watches over your entire repo portfolio and actively maintains it.

Image: `docker.io/prplanit/prplangit`

### Concept

A platform-agnostic daemon with privileged access to GitHub/GitLab/Gitea. If it encounters an opt-in manifest in a repo, it fires the instructions. Independent of GitHub Actions or GitLab CI. Everything done via MRs with an auto-accept option for people who want to YOLO.

**Positioning:** "The maintainer you wish you had." It does the tedious hygiene work that every repo needs but nobody wants to do.

### Feature Matrix

| Feature | Existing tools (fragmented) |
|---|---|
| Readme badges/flair management | Shields.io (manual) |
| Dependency updates | Renovate, Dependabot (standalone) |
| Security scanning | Snyk, Socket, Trivy (standalone) |
| Cross-provider doc sync | Nothing good exists |
| Fork maintenance with patch preservation | **Nothing exists** |
| Pre-build supply chain sleuthing | Socket.dev is closest |
| Repo lander quality advice | **Nothing exists** |
| DockerHub readme sync | A few janky Actions |
| Auto-MR with YOLO auto-accept | **Nothing exists as a unified feature** |

### Unique Differentiators (No Real Competitor)

- **Fork maintenance mode** - keeping a patched fork current with upstream while preserving your changes and scanning for safety. People do this manually and it sucks.
- **Cross-provider sync** - DockerHub readme, GitHub/GitLab mirror description parity, link resolution verification.
- **Unified stewardship** - Replaces the patchwork of Renovate + Snyk + Trivy + manual badge maintenance + manual fork rebases.
- **Zero-config discovery** - daemon scans repos for opt-in manifests automatically, no per-repo registration required.

### Key Features

- **Repo flair/badges** - Auto-manage README badges (build status, coverage, security score, etc.) across all repos
- **Auto-fire Renovate** - Built-in dependency update automation
- **MR-based workflow** - Everything via merge requests, with auto-accept option for YOLO users
- **Post-build security scanning** - SAST/DAST/container scanning after builds
- **Security info embedding** - Making security info visible on platforms that make it hard
- **Repo lander advice** - Helping users with complicated README/landing pages
- **Documentation/repo sync across providers** - Syncing READMEs, DockerHub descriptions, ensuring links work across mirrors
- **Fork maintenance** - Keep forks current, push timely updates, maintain patches, scan for safety as best effort
- **Supply chain attack prevention** - Centralized builds with pre-build diagnostics on all dependencies per repo. Sleuthing runs against package-level threats.

### Market Angle

The supply chain angle is legitimately strong given xz-utils, polyfill.io, and constant npm/PyPI attacks. Centralizing pre-build dependency auditing across an entire org's repos is a real sell to security teams.

The YOLO auto-accept MR mode would drive adoption from solo devs and homelab people fast.

### Branding

Name `prplangit` = "PR Plan Git" hiding inside the PrecisionPlan IT brand with one letter swap. Every PR it opens, every bot comment, every branch name (`prplangit/update-dependencies`) is free brand impressions embedded in developer workflows. The tool markets itself every time it does its job.

### Rejected/Alternative Names

- **StageFreight** - stage fright + freight/shipping pun. Clever but doesn't market the brand.
- **PassRover** - pass-rover, a rover that passes over repos. Friendly, avoidable religious connotation.
- **PassOverRover** - same concept, longer.
- **RedPaintRover** - original Passover/blood-on-doorpost reference. Memorable, tells a story, good mascot potential.
- **Gityankee** - BG3 Githyanki pun. Hilarious.
