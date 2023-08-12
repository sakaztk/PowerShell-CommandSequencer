Push-Location $PSScriptRoot
$modulePath = Split-Path -Parent $PSScriptRoot

Import-Module $modulePath -Force
Invoke-PSCommandSequencer #-Verbose
Pop-Location
