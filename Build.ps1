$ErrorActionPreference = 'Stop'
$taskProject = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path -LiteralPath (Join-Path $taskProject 'build-profile.json5'))) {
    Copy-Item -LiteralPath (Join-Path $taskProject 'build-profile.example.json5') -Destination (Join-Path $taskProject 'build-profile.json5')
}
$taskStudio = 'E:\HarmonyDev\tools\DevEcoStudio'
$env:TEMP = 'E:\HarmonyDev\temp'
$env:TMP = $env:TEMP
$env:HVIGOR_USER_HOME = 'E:\HarmonyDev\cache\nua-hvigor'
$env:DEVECO_SDK_HOME = Join-Path $taskStudio 'sdk'
$env:JAVA_HOME = Join-Path $taskStudio 'jbr'
$taskDependencies = 'E:\HarmonyDev\cache\nua-tools\node_modules'
# exFAT cannot host pnpm's junctions. Copy the already installed SDK tools to an
# isolated E-drive cache, without changing the SDK or any unrelated project.
foreach ($taskPackage in @('hvigor', 'hvigor-ohos-plugin')) {
    $taskTarget = Join-Path $taskDependencies ('@ohos\' + $taskPackage)
    if (-not (Test-Path -LiteralPath (Join-Path $taskTarget 'package.json'))) {
        New-Item -ItemType Directory -Force -Path $taskTarget | Out-Null
        & robocopy (Join-Path $taskStudio ('tools\hvigor\' + $taskPackage)) $taskTarget /E /NFL /NDL /NJH /NJS /NP
        if ($LASTEXITCODE -ge 8) { throw 'Bundled build-tool cache copy failed.' }
    }
}
$env:NODE_PATH = $taskDependencies
$env:PATH = (Join-Path $env:JAVA_HOME 'bin') + ';' + (Join-Path $taskStudio 'sdk\default\hms\toolchains\lib') + ';' + (Join-Path $taskStudio 'sdk\default\openharmony\previewer\common\bin') + ';' + $env:PATH
Push-Location $taskProject
try {
    & 'E:\HarmonyDev\tools\node-v24.16.0-win-x64\node.exe' (Join-Path $taskDependencies '@ohos\hvigor\bin\hvigor.js') --mode module -p product=default -p buildMode=debug assembleHap --no-daemon @args
    if ($LASTEXITCODE -ne 0) { throw 'Harmony build failed; original Android projects are untouched.' }
} finally { Pop-Location }
