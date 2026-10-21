# EOL dependency use. Prefer elevated.
# Measure does not change auditing. It prints Security-log size and the current 4663 pace.
# Watch arms execute-audit on sentinel DLLs only, then prints which process loaded them.
# Event text is not saved. Watch removes the rules when the pace is already over 64 MB/day.
# -Dependency limits the families. Omit it for the built-in EOL set. All includes DotNet8.

# Measure every built-in EOL family
#!ps
#timeout=600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','EolDependencyAudit-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/EolDependencyAudit/Invoke-EolDependencyAudit.ps1?ref=main'); & ([scriptblock]::Create($script)) -Action Measure -Exit

# Measure one family
#!ps
#timeout=600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','EolDependencyAudit-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/EolDependencyAudit/Invoke-EolDependencyAudit.ps1?ref=main'); & ([scriptblock]::Create($script)) -Action Measure -Dependency VC2012 -Exit

# 10-minute sample of added log cost, then remove the audit rules
#!ps
#timeout=900000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','EolDependencyAudit-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/EolDependencyAudit/Invoke-EolDependencyAudit.ps1?ref=main'); & ([scriptblock]::Create($script)) -Action Measure -SampleMinutes 10 -Dependency VC2012 -Exit

# Arm sentinel auditing when the current pace is under 64 MB/day, then list hits
#!ps
#timeout=600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','EolDependencyAudit-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/EolDependencyAudit/Invoke-EolDependencyAudit.ps1?ref=main'); & ([scriptblock]::Create($script)) -Action Watch -Exit

# Remove this script's execute-audit rules
#!ps
#timeout=600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','EolDependencyAudit-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/EolDependencyAudit/Invoke-EolDependencyAudit.ps1?ref=main'); & ([scriptblock]::Create($script)) -Action Disable -Exit

# Domain controller. Downloads the installer, which downloads the audit script and creates the GPO.
# Dry-run does not write SYSVOL. The live command links at the domain root and includes servers.
# Prefer -TargetOU 'OU=Workstations,DC=contoso,DC=com' instead of -LinkToDomain for a pilot.

# GPO dry-run
#!ps
#timeout=300000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','EolDependencyAuditGpo-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/EolDependencyAudit/Install-EolDependencyAuditGpo.ps1?ref=main'); & ([scriptblock]::Create($script)) -Action Watch -DryRun -Exit

# GPO create and link at the domain root
#!ps
#timeout=600000
#maxlength=200000
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','EolDependencyAuditGpo-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/EolDependencyAudit/Install-EolDependencyAuditGpo.ps1?ref=main'); & ([scriptblock]::Create($script)) -Action Watch -LinkToDomain -Exit
