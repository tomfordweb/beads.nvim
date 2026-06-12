# Demo beads dataset

Synthetic, PII-free `bd` export for a fictional **acme-web** project. Used as
deterministic input for tests and as a stable source for docs screenshots.

Seed a throwaway database from it:

```bash
bd init                                  # in a tmpdir
bd import tests/fixtures/demo/issues.jsonl
```

## What it covers

| id          | status      | type    | note                                  |
|-------------|-------------|---------|---------------------------------------|
| acme-web-1  | in_progress | epic    | parent of acme-web-2                  |
| acme-web-2  | in_progress | feature | parent-child dep on acme-web-1        |
| acme-web-3  | open        | bug     | P0, has comments                      |
| acme-web-4  | open        | task    | **blocked** by acme-web-5             |
| acme-web-5  | open        | task    | blocks acme-web-4                     |
| acme-web-6  | closed      | task    | closed work                           |

Plus one memory (`acme-deploy`). All author fields are neutral
(`demo@example.com` / `Demo User`). No real names, emails, or paths — keep it
that way when extending the dataset.
