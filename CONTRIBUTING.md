# Contributing

## No PII or live secrets

Do not commit personally identifiable information, real client or ticket data, production credentials, API keys, tokens, or private URLs. Use placeholders (e.g. `user@example.com`, `Contoso`) and synthetic examples.

Automated checks: **Gitleaks** runs on pushes and pull requests to `main` (see `.github/workflows/gitleaks.yml`). If a scan fails, remove or redact the finding before merging.

Optional local check (with [Gitleaks](https://github.com/gitleaks/gitleaks) installed):

```bash
gitleaks detect --source . --verbose
```
