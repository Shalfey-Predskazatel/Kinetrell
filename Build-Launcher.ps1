param(
    [Parameter(Mandatory)][ValidateSet('VFG', 'RIFE', 'Combined')][string] $Edition,
    [Parameter(Mandatory)][string] $Destination
)

$ErrorActionPreference = 'Stop'
$target = (New-Item -ItemType Directory -Path $Destination -Force).FullName
if ($Edition -eq 'Combined') {
    $source = 'launcher-rife.c'
    $name = 'RTX Video Player Combined.exe'
} elseif ($Edition -eq 'RIFE') {
    $source = 'launcher-rife.c'
    $name = 'RTX Video Player RIFE.exe'
} else {
    $source = 'launcher-vfg.c'
    $name = 'RTX Video Player.exe'
}

$buildDirectory = Join-Path ([IO.Path]::GetTempPath()) ("rtx-launcher-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $buildDirectory | Out-Null
$resource = Join-Path $buildDirectory 'launcher.o'
Push-Location (Join-Path $PSScriptRoot 'launcher')
try {
    & windres --codepage=65001 launcher.rc -O coff -o $resource
    if ($LASTEXITCODE -ne 0) { throw "windres failed with $LASTEXITCODE" }
    & clang -O2 -Wall -Wextra -municode -mwindows $source $resource -lshell32 -luser32 -o (Join-Path $target $name)
    if ($LASTEXITCODE -ne 0) { throw "clang failed with $LASTEXITCODE" }
} finally {
    Pop-Location
    if (Test-Path -LiteralPath $resource) { Remove-Item -LiteralPath $resource }
    Remove-Item -LiteralPath $buildDirectory
}
