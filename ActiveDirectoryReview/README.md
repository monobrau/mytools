# Active Directory review over RemoteOps

Read-only review of a client's Active Directory, run from this PC. It connects over WinRM to a domain-joined host that is enrolled in RemoteOps, runs the AD queries there, and saves the results here.

Nothing in the domain is changed.

## What it checks

- Domain and forest: functional levels and FSMO role holders
- Domain controllers: site, OS, global catalog, read-only
- Privileged groups, including nested members: Domain Admins, Enterprise Admins, Schema Admins, Administrators, Account Operators, Backup Operators, Server Operators, Print Operators, DnsAdmins, Group Policy Creator Owners
- Stale users and computers: enabled, and no logon in `-InactiveDays` (default 90). Accounts created inside that window are skipped.
- Enabled users whose password never expires
- krbtgt password age
- Trusts

## Requirements

On this PC:

- Elevated PowerShell 5.1 or 7. Connecting by IP address needs a WinRM TrustedHosts entry. The script adds the target for the run and restores the original list afterwards. If it had to start the local WinRM service, it stops it again.
- The host enrolled in RemoteOps, so its tunnel address (Peer IP on the portal) answers on TCP 5985.

On the target:

- WinRM enabled (default on Windows Server)
- The ActiveDirectory module. A domain controller has it. On a member server: `Install-WindowsFeature RSAT-AD-PowerShell`

The account is `DOMAIN\user` and only needs to read the directory. The credential is passed to every AD query on the target, so a member server can reach its domain controller without CredSSP.

## Usage

ScToolLauncher: **Untested → RemoteOps**.

1. **RemoteOps enroll (token)**: issue a token on the portal, paste it, and run the copied `#!ps` on the client host. The portal shows the Peer IP once it connects.
2. **Active Directory review (over tunnel)**: set the Peer IP, paste the one-liner into an elevated PowerShell window on this PC, and enter the domain credential when prompted.
3. **RemoteOps remove**: run on the client host when you are done.

Directly:

```powershell
.\Invoke-ADReview.ps1 -ComputerName 10.88.88.2
.\Invoke-ADReview.ps1 -ComputerName 10.88.88.2 -InactiveDays 60
```

Results go to `Documents\ADReview\<domain>_<timestamp>\`. `-OutputPath` overrides that.

| File | Contents |
| --- | --- |
| `Summary.txt` | Counts and findings. Also printed to the console. |
| `Domain.csv` | Domain, forest, functional levels, FSMO holders, the DC that answered |
| `DomainControllers.csv` | One row per DC |
| `PrivilegedGroupMembers.csv` | One row per group and member. Empty groups show `(no members)`. |
| `StaleUsers.csv`, `StaleComputers.csv` | Enabled accounts past the inactive threshold |
| `PasswordNeverExpires.csv` | Enabled users with a non-expiring password |
| `Users.csv`, `Computers.csv`, `Trusts.csv` | Full lists |

`LastLogonDate` is `lastLogonTimestamp`, which replicates on a 9 to 14 day lag. Treat an account that is only a few days past the threshold as a candidate, not a certainty.
