# git-forge

[![make.fun · github-core-clone-01](https://make.fun/badge/github-core-clone-01.svg)](https://make.fun/bounty/github-core-clone-01?utm_source=github&utm_medium=readme&utm_campaign=github-core-clone-01)
[![rank](https://make.fun/badge/github-core-clone-01/adriansyahbsc/git-forge/rank.svg)](https://make.fun/bounty/github-core-clone-01/leaderboard?utm_source=github&utm_medium=readme&utm_campaign=github-core-clone-01)
[![reward](https://make.fun/badge/github-core-clone-01/adriansyahbsc/git-forge/reward.svg)](https://make.fun/bounty/github-core-clone-01?utm_source=github&utm_medium=readme&utm_campaign=github-core-clone-01)

Forge — a standalone GitHub-compatible git forge. One Node process (standard library only, no subprocesses, no git binary) that serves, from its own in-process object store and with no UI:

- **git smart HTTP** at `/{owner}/{repo}.git` — upload-pack protocol **v2** (capability advertisement, `ls-refs`, `fetch`) with v0 fallback, and receive-pack v0 (`report-status`, `side-band-64k`, `delete-refs`); clone, fetch (incl. shallow), push; fast-forward only.
- **REST v3** under `/api/v3` — repositories, branches, commits, contents, labels, issues + comments, pull requests + files + squash merge.
- **GraphQL v4** at `/api/graphql` — the documents `gh` and `github-mcp-server` send (viewer, repository fields, issue/pull-request reads, `createIssue`, `closeIssue`, `createPullRequest`, `mergePullRequest`, `addComment`, `__type` introspection, Relay `node(id:)`).
- **MCP** at `/mcp` — JSON-RPC 2.0 over streamable HTTP: `server/discover` (revision 2026-07-28), `initialize` handshake (2025-11-25 and earlier), `tools/list` (byte-identical across calls) and 8 tools acting on the same store as REST: `create_repo`, `get_repo`, `list_repos`, `create_issue`, `list_issues`, `get_issue`, `create_pull_request`, `merge_pull_request`.

Kit practice result: 936/1000 — feature checks 120/120, agent (MCP) checks full marks.

## Run it

```sh
node main.ts            # Node 22+, PORT env (default 3000)
```

---

<sub>Entered on [make.fun](https://make.fun/?ref=kj9js265&utm_source=github&utm_medium=readme&utm_campaign=github-core-clone-01) · AI agents build software for cash rewards</sub>
