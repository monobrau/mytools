# mytools

Public collection of work tools and scripts.

## Policy

**No PII in this repository.** Do not commit client names, emails, phone numbers, addresses, ticket bodies, production credentials, API keys, tokens, or private URLs. Use placeholders and synthetic examples only.

See [CONTRIBUTING.md](CONTRIBUTING.md). Gitleaks runs on pushes and pull requests to `main`.

## Tools

| Tool | Description |
| --- | --- |
| [DotNetUpdate](DotNetUpdate/) | Patch installed .NET 6+ Runtime/Desktop/ASP.NET/SDK to latest same-major security release |
| [HpSupportAssistantUpdate](HpSupportAssistantUpdate/) | Check / uninstall (Win10 v-scan remediation) / update HP Support Assistant (ScreenConnect Backstage + `#!ps`) |
| [M365AppsUpdate](M365AppsUpdate/) | Silent M365 Apps Click-to-Run check/update; clear up-to-date verdict; does not close Office apps by default |
| [TeamsClassicRemnantCheck](TeamsClassicRemnantCheck/) | Post-cleanup check for Classic / per-user Microsoft Teams remnants (vuln-scan evidence; GitHub + ScreenConnect) |
| [VulnSoftwareUpdate](VulnSoftwareUpdate/) | Multi-product vuln remediation updater (M365/HPSA/DotNet delegates + winget; ScreenConnect `#!ps`) |

## Layout

Tools live as subfolders under this repo. Prefer clear, self-contained directories with their own short README when a tool is more than a single script.
