# Contributing

## Workflow

1. Every change starts with an issue: a bug report or a feature request.
2. Work on a branch named after the issue. `gh issue develop <issue> --checkout`
   creates `<issue>-<title>`.
3. Open a pull request against `main`. The _Tickets_ check links the issue
   (`Closes #<issue>`); a pull request without a ticket fails.
4. CI runs on every pull request. When all checks are green, _Auto-merge_
   squash-merges it. Open the pull request as a draft while it is not ready.
5. The merge closes the issue. `main` always holds the latest valid state
   (trunk-based development).

## Versions and releases

- Versions follow [Semantic Versioning](https://semver.org) and exist only as
  git tags (`vMAJOR.MINOR.PATCH`).
- CI tags every merge to `main` with the next patch version.
- A release bundles the changes since the previous one: run
  _Actions → Release → Run workflow_ and pick `minor` or `major`. It tags
  `main` and publishes a GitHub release listing the merged pull requests and
  closed tickets.

## Development

```
pip install -r requirements-dev.txt   # ruff, pytest, matplotlib
ruff check .                         # lint the harness, tools and Python solvers
shellcheck tools/*.sh
pytest tests                         # reference solver, harness, report and Python solvers
```

CI additionally builds every implementation and checks it against the
reference solutions (`python3 bench/run.py --verify`, `tools/contract_test.sh`,
`tools/crosscheck.sh`). Benchmark results from the manual `benchmark` workflow
arrive as an artifact; commit them like any other change.
