# ScreenConnect GPO deploy

Run elevated as a Domain Admin on a DC or RSAT box. Point it at the **client MSI** downloaded from your ScreenConnect instance (the Access installer, already configured for that instance).

The script copies that MSI to `\\<domain>\NETLOGON\ScreenConnect\<name>\` and creates a GPO Immediate Task. The task runs as SYSTEM at the next Group Policy refresh and installs only when no `ScreenConnect Client*` service exists. A reboot is not required to start it.

`-LinkToDomain` attaches the workstation WMI filter (`ProductType = 1`) so domain controllers do not install the client. Prefer a pilot OU with `-TargetOU` first.

```powershell
.\Install-ScreenConnectGPO.ps1 -MsiPath 'C:\Support\ScreenConnect.ClientSetup.msi' -ClientName 'Contoso' -DryRun
.\Install-ScreenConnectGPO.ps1 -MsiPath 'C:\Support\ScreenConnect.ClientSetup.msi' -ClientName 'Contoso' -TargetOU 'OU=Workstations,DC=contoso,DC=com'
```

Log on a workstation: `C:\Windows\Temp\ScreenConnect-GPO-Install.log`.
