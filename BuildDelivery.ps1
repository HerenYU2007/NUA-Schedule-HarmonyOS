$ErrorActionPreference = 'Stop'
$taskProject = Split-Path -Parent $MyInvocation.MyCommand.Path
$taskDeliveryRoot = 'E:\HarmonyDev\deliveries'
$taskDelivery = Join-Path $taskDeliveryRoot ('nua-harmony-parity-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$taskSource = Join-Path $taskDelivery 'source\NUA-Schedule-HarmonyOS'
New-Item -ItemType Directory -Force -Path $taskSource | Out-Null
foreach ($taskFolder in @('AppScope','tools','updates','hvigor')) {
    Copy-Item -LiteralPath (Join-Path $taskProject $taskFolder) -Destination $taskSource -Recurse
}
$taskEntry = Join-Path $taskSource 'entry'
New-Item -ItemType Directory -Force -Path $taskEntry | Out-Null
& robocopy (Join-Path $taskProject 'entry\src') (Join-Path $taskEntry 'src') /E /XF PersonalRules.ets /NFL /NDL /NJH /NJS /NP
if ($LASTEXITCODE -ge 8) { throw 'Source copy failed.' }
foreach ($taskName in @('build-profile.json5','hvigorfile.ts','oh-package.json5')) {
    Copy-Item -LiteralPath (Join-Path $taskProject ('entry\' + $taskName)) -Destination $taskEntry
}
foreach ($taskName in @('.gitignore','Build.ps1','BuildDelivery.ps1','build-profile.example.json5','hvigorfile.ts','oh-package.json5','README.md','CHANGELOG.md','MIGRATION-ANDROID-1.2.4.md','LICENSE')) {
    Copy-Item -LiteralPath (Join-Path $taskProject $taskName) -Destination $taskSource
}
# Never copy the machine's root build-profile.json5, signing material or personal timetable fixture.
$taskForbidden = Get-ChildItem -LiteralPath $taskSource -File -Recurse | Where-Object { $_.Extension -in @('.p12','.p7b','.cer','.key','.pem','.jks','.keystore','.xls','.xlsx') -or $_.Name -eq 'agconnect-services.json' }
if ($taskForbidden.Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $taskSource 'build-profile.json5'))) { throw 'Private files found in delivery source.' }
$taskPackage = Join-Path $taskDelivery 'packages'
New-Item -ItemType Directory -Force -Path $taskPackage | Out-Null
foreach ($taskName in @('entry-default-signed.hap','entry-default-unsigned.hap')) {
    Copy-Item -LiteralPath (Join-Path $taskProject ('entry\build\default\outputs\default\' + $taskName)) -Destination $taskPackage
}
Compress-Archive -LiteralPath $taskSource -DestinationPath (Join-Path $taskDelivery 'NUA-Schedule-HarmonyOS-source.zip')
Get-ChildItem -LiteralPath $taskPackage -File | Get-FileHash -Algorithm SHA256 | Select-Object Hash,Path
Write-Output ('Delivery: ' + $taskDelivery)
