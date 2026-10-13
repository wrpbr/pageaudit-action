# PageAudit preview check

Catch SEO mistakes before they reach production. On every deploy preview, this step audits the preview and the same
page in production with [PageAudit](https://pageaudit.online), compares them by finding code, and writes only what
got worse in the job summary: a page that now asks not to be indexed, a broken canonical, a missing title or link
preview, robots rules that block search engines. It reports by default and can fail the job on a regression.

## Use

With a host that publishes previews as GitHub deployments (Vercel, Netlify, Cloudflare Pages and others):

```yaml
on: deployment_status
permissions:
  contents: read
jobs:
  seo:
    if: github.event.deployment_status.state == 'success'
    runs-on: ubuntu-latest
    steps:
      - uses: wrpbr/pageaudit-action@v1
        with:
          url: ${{ github.event.deployment_status.target_url }}
          production-url: https://example.com/
          fail-on: regression
```

Without `production-url`, the step compares with the repository's website (the About field), when it is set. With
neither, it checks the page alone and lists the error-level findings.

## Inputs

| Input | Default | What it does |
|---|---|---|
| `url` | — | The page to check, usually the preview URL. Required. |
| `production-url` | repository website | The same page in production, to compare with. |
| `fail-on` | `none` | `none` reports only; `regression` fails when the page is worse than production; `error` fails on any error-level finding. |
| `api-key` | — | Your PageAudit account API key, from a secret. Audits then count on your account. |
| `pageaudit-url` | `https://pageaudit.online` | PageAudit address. |

Outputs: `score`, `regression` and `new-findings`.

## How it works

Without a key, the step gets a temporary guest identity for the run, audits production, then audits the preview
with `compare_with` set to the production audit. PageAudit compares the findings by code, not by message, so a
measured value that changes does not count as a new problem. A regression is a lower score or a new error or
warning; a new informational finding alone is not. The script is plain `bash`, `curl` and `jq`; pin it by commit SHA
if your policy requires it.

Each check uses two audits: production and the preview. Audits have a free daily allowance; the current limits and
prices are at https://pageaudit.online/pricing.

## With an agent

The same check runs from the PageAudit MCP server (`https://pageaudit.online/mcp`): the `audit_url` tool takes
`compare_with`, and `get_patch` returns the ready fix. The GitHub Copilot coding agent can use it from the repository
settings, under Copilot → MCP servers.

## License

MIT. The PageAudit service follows its [terms of use](https://pageaudit.online/terms) and
[privacy policy](https://pageaudit.online/privacy). Questions: open an issue or write to contato@pageaudit.online.
