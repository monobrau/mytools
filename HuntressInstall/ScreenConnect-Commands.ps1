# Huntress silent install for ScreenConnect.
# Paste real -AccountKey / -OrgKey at run time (ScToolLauncher). Never commit keys.
# Uses official /ACCT_KEY= (not /ACCOUNT_KEY=).
# PS2-safe: download the vendor EXE directly (no GitHub, no #Requires 5.1).

#!ps
#timeout=600000
#maxlength=200000
try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{try{[Net.ServicePointManager]::SecurityProtocol=3072}catch{}}
$acct='YOUR_ACCOUNT_KEY'
$org='YOUR_ORG_KEY'
$tags=''
$svc=Get-Service -Name HuntressAgent -EA SilentlyContinue
$exes=@((Join-Path $env:ProgramFiles 'Huntress\HuntressAgent.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Huntress\HuntressAgent.exe'))
$hit=$false
if($svc){$hit=$true; Write-Output ('Service HuntressAgent: '+[string]$svc.Status)}
foreach($e in $exes){if($e -and (Test-Path -LiteralPath $e)){$hit=$true; Write-Output ('Found '+$e)}}
if($hit){Write-Output 'Huntress agent already present. Skipping.'; exit 0}
$out=Join-Path $env:TEMP 'HuntressInstaller.exe'
Write-Output 'Downloading Huntress installer (update.huntress.io)'
$wc=New-Object Net.WebClient
$wc.DownloadFile(('https://update.huntress.io/download/'+$acct+'/HuntressInstaller.exe'),$out)
if(-not(Test-Path -LiteralPath $out) -or ((Get-Item -LiteralPath $out).Length -eq 0)){throw 'Huntress download failed or 0 bytes'}
$a='/ACCT_KEY='+$acct+' /ORG_KEY='+$org
if($tags){$a+=' /TAGS='+$tags}
$a+=' /S'
Write-Output 'Installing with official /ACCT_KEY='
$p=Start-Process -FilePath $out -ArgumentList $a -Wait -PassThru
Write-Output ('Installer exit '+$p.ExitCode)
Remove-Item -LiteralPath $out -Force -EA SilentlyContinue
exit $p.ExitCode
