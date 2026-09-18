#!ps
#timeout=900000
#maxlength=200000
# Huntress silent install. #!ps + #timeout must be first or SC defaults to 60s.
# $force=$true = in-session rip and replace (no reboot).
# $schedule=$true = SYSTEM tasks + cleanup in 30 min + reboot at $rebootAt (host local).
# Official /ACCT_KEY= (not /ACCOUNT_KEY=).
try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{try{[Net.ServicePointManager]::SecurityProtocol=3072}catch{}}
$acct='fddd1009b6541feb66431b905f6fc870'
$org='YOUR_ORG_KEY'
$tags=''
$force=$false
$schedule=$false
$rebootAt='' # required when $schedule; host-local e.g. '2026-09-18 17:30'
if(-not $acct -or $acct.Length -ne 32 -or $acct -eq 'YOUR_ACCOUNT_KEY'){throw ('Bad Huntress account key length '+[string]$acct.Length+' (need 32).')}
if(-not $org -or $org -eq 'YOUR_ORG_KEY'){throw 'Set $org to the Huntress organization key (client short name).'}
$svc=Get-Service -Name HuntressAgent -EA SilentlyContinue
if($schedule){
  if(-not $rebootAt){throw 'Set $rebootAt to host-local yyyy-MM-dd HH:mm'}
  $when=Get-Date $rebootAt
  $sec=[int][math]::Ceiling(($when-(Get-Date)).TotalSeconds)
  if($sec -lt 60){throw ('Reboot time is in the past or <60s: '+$rebootAt+' host now '+(Get-Date -Format 'yyyy-MM-dd HH:mm'))}
  if(-not $force -and $svc){Write-Output ('Service HuntressAgent: '+[string]$svc.Status); Write-Output 'Already installed. Set $force=$true to wipe in the scheduled job.'; exit 0}
  $dir='C:\Windows\Temp'
  $job=Join-Path $dir 'Huntress-SC-Install.ps1'
  $clean=Join-Path $dir 'Huntress-SC-Cleanup.ps1'
  $jlog=Join-Path $dir 'Huntress-SC-Install.log'
  $forceLit= if($force){'$true'}else{'$false'}
  $jobLines=@(
    "try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}"
    "function L(`$m){ Add-Content -LiteralPath '$jlog' -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+' '+`$m) }"
    "L 'Huntress-SC-Install start'"
    "`$acct='$acct'"
    "`$org='$org'"
    "`$tags='$tags'"
    "`$force=$forceLit"
    "if(`$force){ L 'wipe'; foreach(`$n in @('HuntressRio','HuntressUpdater','HuntressAgent','Huntmon')){ Stop-Service `$n -Force -EA SilentlyContinue }; `$tk= if(Test-Path (`$env:SystemRoot+'\SysNative\taskkill.exe')){ `$env:SystemRoot+'\SysNative\taskkill.exe' } else { `$env:SystemRoot+'\System32\taskkill.exe' }; foreach(`$im in @('HuntressInstaller.exe','HuntressAgent.exe','HuntressUpdater.exe','HuntressRio.exe')){ & `$tk /F /T /IM `$im }; foreach(`$d in @((Join-Path `$env:ProgramFiles 'Huntress'),(Join-Path `${env:ProgramFiles(x86)} 'Huntress'))){ `$u=Join-Path `$d 'Uninstall.exe'; if(Test-Path `$u){ Start-Process `$u -ArgumentList '/S' -Wait -EA SilentlyContinue }; if(Test-Path `$d){ Remove-Item `$d -Recurse -Force -EA SilentlyContinue } }; foreach(`$k in @('HKLM:\SOFTWARE\Huntress Labs','HKLM:\SOFTWARE\WOW6432Node\Huntress Labs')){ if(Test-Path `$k){ Remove-Item `$k -Recurse -Force -EA SilentlyContinue } }; foreach(`$n in @('HuntressRio','HuntressUpdater','HuntressAgent','Huntmon')){ sc.exe delete `$n | Out-Null }; L 'wipe done' }"
    "`$out=Join-Path `$env:TEMP 'HuntressInstaller.exe'"
    "L 'download'"
    "`$wc=New-Object Net.WebClient"
    "`$wc.DownloadFile(('https://update.huntress.io/download/'+`$acct+'/HuntressInstaller.exe'),`$out)"
    "if(-not(Test-Path `$out) -or ((Get-Item `$out).Length -eq 0)){ L 'download failed'; exit 4 }"
    "L ('downloaded '+[string]((Get-Item `$out).Length))"
    "`$q=[char]34; `$a=('/ACCT_KEY='+`$q+`$acct+`$q+' /ORG_KEY='+`$q+`$org+`$q); if(`$tags){`$a+=' /TAGS='+`$q+`$tags+`$q}; `$a+=' /S'"
    "L 'start installer'"
    "`$p=Start-Process -FilePath `$out -ArgumentList `$a -PassThru"
    "`$n=0; while(`$p -and -not `$p.HasExited -and `$n -lt 900){ Start-Sleep 15; `$n+=15; try{`$p.Refresh()}catch{}; L ('installing '+[string]`$n+'s') }"
    "if(`$p -and -not `$p.HasExited){ L 'installer still running after 900s; leaving it' } elseif(`$p){ L ('installer exit '+[string]`$p.ExitCode) }"
    "Get-Service HuntressAgent -EA SilentlyContinue | ForEach-Object { L ('service '+[string]`$_.Status) }"
    "L 'Huntress-SC-Install end'"
  )
  Set-Content -LiteralPath $job -Value $jobLines -Encoding ASCII
  $cleanLines=@(
    "Start-Sleep -Seconds 1800"
    "Get-Process HuntressInstaller -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue"
    "Remove-Item -LiteralPath 'C:\Windows\Temp\HuntressInstaller.exe' -Force -EA SilentlyContinue"
    "Remove-Item -LiteralPath 'C:\Windows\Temp\Huntress-SC-Install.ps1' -Force -EA SilentlyContinue"
    "schtasks.exe /Delete /TN HuntressSC-Install /F"
    "schtasks.exe /Delete /TN HuntressSC-Cleanup /F"
    "Remove-Item -LiteralPath 'C:\Windows\Temp\Huntress-SC-Cleanup.ps1' -Force -EA SilentlyContinue"
  )
  Set-Content -LiteralPath $clean -Value $cleanLines -Encoding ASCII
  $ps= if(Test-Path -LiteralPath "$env:SystemRoot\SysNative\WindowsPowerShell\v1.0\powershell.exe"){ "$env:SystemRoot\SysNative\WindowsPowerShell\v1.0\powershell.exe" } else { "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
  $trInstall=('"'+$ps+'" -NoProfile -ExecutionPolicy Bypass -File "'+$job+'"')
  $trClean=('"'+$ps+'" -NoProfile -ExecutionPolicy Bypass -File "'+$clean+'"')
  schtasks.exe /Create /TN HuntressSC-Install /RU SYSTEM /RL HIGHEST /SC ONCE /ST 23:59 /F /TR $trInstall
  schtasks.exe /Create /TN HuntressSC-Cleanup /RU SYSTEM /RL HIGHEST /SC ONCE /ST 23:59 /F /TR $trClean
  schtasks.exe /Run /TN HuntressSC-Install
  schtasks.exe /Run /TN HuntressSC-Cleanup
  shutdown.exe /r /t $sec /c ('Huntress SC reboot '+$rebootAt)
  Write-Output ('Scheduled HuntressSC-Install + HuntressSC-Cleanup (+30 min). Reboot at '+$rebootAt+' (in '+[string]$sec+'s). Abort reboot: shutdown /a')
  Write-Output 'Log: C:\Windows\Temp\Huntress-SC-Install.log'
  exit 0
}
$exes=@((Join-Path $env:ProgramFiles 'Huntress\HuntressAgent.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Huntress\HuntressAgent.exe'))
if($force){
  Write-Output '=== Rip and replace (no reboot) ==='
  foreach($n in @('HuntressRio','HuntressUpdater','HuntressAgent','Huntmon')){ Stop-Service $n -Force -EA SilentlyContinue }
  $tk= if(Test-Path -LiteralPath "$env:SystemRoot\SysNative\taskkill.exe"){ "$env:SystemRoot\SysNative\taskkill.exe" } else { "$env:SystemRoot\System32\taskkill.exe" }
  foreach($im in @('HuntressInstaller.exe','HuntressAgent.exe','HuntressUpdater.exe','HuntressRio.exe','Huntmon.exe')){ Write-Output ($tk+' /F /T /IM '+$im); & $tk /F /T /IM $im }
  $dirs=@((Join-Path $env:ProgramFiles 'Huntress'),(Join-Path ${env:ProgramFiles(x86)} 'Huntress'))
  foreach($d in $dirs){
    $u=Join-Path $d 'Uninstall.exe'
    if(Test-Path -LiteralPath $u){ Write-Output ('Running '+$u+' /S'); $up=Start-Process -FilePath $u -ArgumentList '/S' -PassThru; $w=0; while($up -and -not $up.HasExited -and $w -lt 45){ Start-Sleep -Seconds 3; $w+=3; try{$up.Refresh()}catch{} } }
  }
  Start-Sleep -Seconds 2
  foreach($im in @('HuntressInstaller.exe','HuntressAgent.exe','HuntressUpdater.exe','HuntressRio.exe')){ & $tk /F /T /IM $im | Out-Null }
  $left=@(Get-Process | Where-Object { $_.Name -like '*Huntress*' -and -not $_.HasExited })
  if($left.Count -gt 0){ $left | ForEach-Object { Write-Output ('STILL ALIVE '+$_.Name+' PID '+[string]$_.Id+' (HasExited='+[string]$_.HasExited+')') }; Write-Output 'Live Huntress process still running; install will likely hang. Reboot or use Schedule option.' }
  foreach($d in $dirs){ if(Test-Path -LiteralPath $d){ Remove-Item -LiteralPath $d -Recurse -Force -EA SilentlyContinue; Write-Output ('Removed '+$d) } }
  foreach($k in @('HKLM:\SOFTWARE\Huntress Labs','HKLM:\SOFTWARE\WOW6432Node\Huntress Labs')){ if(Test-Path $k){ Remove-Item $k -Recurse -Force -EA SilentlyContinue; Write-Output ('Removed '+$k) } }
  foreach($n in @('HuntressRio','HuntressUpdater','HuntressAgent','Huntmon')){ sc.exe delete $n | Out-Null }
  Write-Output 'Wipe done; installing in this session (no reboot)'
} else {
  if($svc){Write-Output ('Service HuntressAgent: '+[string]$svc.Status); Write-Output 'Huntress agent already present. Skipping. Set $force=$true to rip and replace.'; exit 0}
  Write-Output 'Service HuntressAgent: not found'
  foreach($e in $exes){if($e -and (Test-Path -LiteralPath $e)){Write-Output ('Leftover '+$e+' (no service; continuing install)')}}
}
$out=Join-Path $env:TEMP 'HuntressInstaller.exe'
Write-Output ('Downloading Huntress installer (update.huntress.io, key length '+[string]$acct.Length+')')
$wc=New-Object Net.WebClient
$wc.DownloadFile(('https://update.huntress.io/download/'+$acct+'/HuntressInstaller.exe'),$out)
if(-not(Test-Path -LiteralPath $out) -or ((Get-Item -LiteralPath $out).Length -eq 0)){throw 'Huntress download failed or 0 bytes'}
Write-Output ('Downloaded '+[string]((Get-Item -LiteralPath $out).Length)+' bytes')
$q=[char]34
$a=('/ACCT_KEY='+$q+$acct+$q+' /ORG_KEY='+$q+$org+$q)
if($tags){$a+=' /TAGS='+$q+$tags+$q}
$a+=' /S'
Write-Output 'Installing with official /ACCT_KEY= (heartbeat every 10s; no reboot)'
$p=Start-Process -FilePath $out -ArgumentList $a -PassThru
if(-not $p){throw 'Start-Process returned no installer process'}
Write-Output ('Installer PID '+[string]$p.Id)
$n=0
while(-not $p.HasExited -and $n -lt 240){ Start-Sleep -Seconds 10; $n+=10; try{$p.Refresh()}catch{}; Write-Output ('Installing... '+[string]$n+'s PID '+[string]$p.Id) }
$log='C:\Windows\Temp\HuntressInstaller.log'
if(-not $p.HasExited){
  Write-Output 'Installer still running after 240s (not killed). Check services and log.'
  if(Test-Path -LiteralPath $log){ Write-Output ('--- '+$log+' ---'); Get-Content -LiteralPath $log | Select-Object -Last 20 | ForEach-Object { Write-Output $_ } }
  Get-Service -Name HuntressAgent -EA SilentlyContinue | ForEach-Object { Write-Output ('Service HuntressAgent: '+[string]$_.Status) }
  exit 0
}
Write-Output ('Installer exit '+[string]$p.ExitCode)
if(Test-Path -LiteralPath $log){ Write-Output ('--- '+$log+' ---'); Get-Content -LiteralPath $log | Select-Object -Last 15 | ForEach-Object { Write-Output $_ } }
Get-Service -Name HuntressAgent -EA SilentlyContinue | ForEach-Object { Write-Output ('Service HuntressAgent: '+[string]$_.Status) }
Remove-Item -LiteralPath $out -Force -EA SilentlyContinue
exit $p.ExitCode
