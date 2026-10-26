# Vulnerable CPython cleanup. Scan first. Remove does not install a replacement and does not reboot.
# A newer Python on the same PC does not keep an older one.

# Scan
#!ps
#timeout=300000
#maxlength=200000
if($PSVersionTable.PSVersion.Major -lt 5){$exe=$null; foreach($c in @("$env:SystemRoot\SysNative\WindowsPowerShell\v1.0\powershell.exe","$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe","$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe")){if(Test-Path -LiteralPath $c){try{$v=& $c -NoProfile -Command '$PSVersionTable.PSVersion.Major'}catch{$v=0}; if(($v -as [int]) -ge 5){$exe=$c; break}}}; if(-not $exe){throw 'PowerShell 5.1 required (this host has only 2.0). Install WMF 5.1.'}; & $exe -NoProfile -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path; exit $LASTEXITCODE}; $ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','PythonCleanup-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/PythonCleanup/Uninstall-VulnerablePython.ps1?ref=main'); if ($script -match '(?i)<html|github.com/login|&redirect') { throw 'Download returned HTML, not a script.' }; & ([scriptblock]::Create($script)) -CheckOnly -Exit

# Remove
#!ps
#timeout=1800000
#maxlength=200000
if($PSVersionTable.PSVersion.Major -lt 5){$exe=$null; foreach($c in @("$env:SystemRoot\SysNative\WindowsPowerShell\v1.0\powershell.exe","$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe","$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe")){if(Test-Path -LiteralPath $c){try{$v=& $c -NoProfile -Command '$PSVersionTable.PSVersion.Major'}catch{$v=0}; if(($v -as [int]) -ge 5){$exe=$c; break}}}; if(-not $exe){throw 'PowerShell 5.1 required (this host has only 2.0). Install WMF 5.1.'}; & $exe -NoProfile -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path; exit $LASTEXITCODE}; $ProgressPreference='SilentlyContinue'; try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}; $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','PythonCleanup-bootstrap/1.0.0'); $wc.Headers.Add('Accept','application/vnd.github.raw'); $script=$wc.DownloadString('https://api.github.com/repos/monobrau/mytools/contents/PythonCleanup/Uninstall-VulnerablePython.ps1?ref=main'); if ($script -match '(?i)<html|github.com/login|&redirect') { throw 'Download returned HTML, not a script.' }; & ([scriptblock]::Create($script)) -Remediate -Exit
