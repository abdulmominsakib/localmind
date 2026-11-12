---
title: Upgrade Checklist
---

Use this checklist when upgrading `llamadart` across minor/major versions.

## 1. Read release notes first

- Start with [Recent Releases](../changelog/recent-releases)
- Then review full `CHANGELOG.md`

## 2. Review migration guides

- Primary migration reference: [`MIGRATION.md`](https://github.com/leehack/llamadart/blob/main/MIGRATION.md)
- 0.4.x -> 0.5.x specifics: [Migration (0.4.x to 0.5.x)](./0-4-to-0-5)
- 0.5.x -> 0.6.x specifics: [Migration (0.5.x to 0.6.x)](./0-5-to-0-6)

## 3. Validate build/runtime behavior

- Run `dart analyze`
- Run `dart test`
- Run platform-specific smoke checks for your deployment targets

## 4. Validate template and tool-calling behavior

- Re-run critical prompt/tool scenarios with production-like settings
- Confirm any custom template assumptions still apply

## 5. Validate deployment/runtime pins

- Confirm native runtime bundle expectations
- Confirm web bridge asset tags and compatibility rules

## 6. Update docs for your team/app

- Capture changed defaults, removed APIs, and new flags
- Link your internal runbooks to the exact release tag
