<#
param
(
    [string]$UICulture = $PSUICulture
)

if (Test-Path -Path "${PSScriptRoot}\${PSUICulture}")
{
    Import-LocalizedData localizedData `
        -BaseDirectory $PSScriptRoot `
        -FileName PSCommand-Sequencer.Strings.psd1 `
        -UICulture $PSUICulture
}
else
{
    Import-LocalizedData localizedData `
        -BaseDirectory $PSScriptRoot `
        -FileName PSCommand-Sequencer.Strings.psd1 `
        -UICulture 'en-US'
}
#>

function script:Import-ModuleFolder {
    [CmdletBinding()]
    Param (
        [String[]]$Path
    )
    Process {
        try
        {
            $Path | ForEach-Object {
                Get-ChildItem $_ | ForEach-Object {
                    Import-Module $_.FullName -Force
                    Write-Verbose "Imported $_.Name."
                }
            }          
        }
        catch {
            throw
        }
    }
}

function script:Import-DataFile {
    [CmdletBinding()]
    Param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [String]$Path
    )
    Process {
        $fileExtension = [System.IO.Path]::GetExtension($Path)
        try {
            switch ($fileExtension) {
                ".xml" {
                    Import-Clixml $Path
                }
                ".psd1" {
                    Invoke-Expression (Get-Content $path -raw)
                }
                ".json" {
                    ConvertFrom-Json -InputObject (Get-Content $Path -Raw)
                }
                {$_ -in 'yml', '.yaml'} {
                    if (Get-Command 'ConvertTo-Yaml' -ErrorAction SilentlyContinue) {
                        ConvertFrom-Yaml -yaml (Get-Content $Path -Raw)
                    }
                    else {
                        throw 'Module "Powershell-Yaml" needed.'
                    }
                }
                ".csv" {
                    Import-Csv -Path $Path -Encoding UTF8
                }
                default {
                    throw "File type not supported."
                }
            }
            Write-Verbose "Imported $_."
        }
        catch {
            throw
        }
    }
}

function script:Export-DataFile {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [PSObject[]]$InputObject
        ,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    Process {
        $fileExtension = [System.IO.Path]::GetExtension($Path)
        switch($fileExtension) {
            ".xml" {
                $InputObject | Export-Clixml -Path $Path -Encoding UTF8 -Force
            }
            ".json" {
                $InputObject | ConvertTo-Json | Out-File $Path -Encoding UTF8 -Force
            }
            {$_ -in 'yml', '.yaml'} {
                if (Get-Command 'ConvertTo-Yaml' -errorAction SilentlyContinue) {
                    $InputObject = $InputObject | ConvertTo-Json | ConvertFrom-Json  #error may occur when convertto-yaml if remove this line.
                    $InputObject | ConvertTo-Yaml | Out-File $Path -Encoding UTF8 -Force
                }
                else {
                    throw 'Module "Powershell-Yaml" needed.'
                }
            }
            ".csv" {
                $InputObject | Export-Csv -Path $Path -Encoding UTF8 -NoTypeInformation
            }
            default {
                throw "File type $_ not supported."
            }
        }
    }
}

function script:Invoke-Procedure {
    [CmdletBinding()]
    Param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [PSObject]$targetTask
    )
    Process
    {
        if (
            ($targetTask.Target -eq 'all') `
            -or ($InventoryData.Role -in $targetTask.Target) `
            -or ($env:COMPUTERNAME -in $targetTask.Target)
        ) {
            try {
                $return = (Invoke-Expression $targetTask.Command) 2>&1
                if ($return.Exception) {
                    throw $return.Exception
                }
                if ($null -eq $targetTask.expect) {
                    $result = '-'
                }
                else {
                    if ($return -eq $targetTask.expect) {
                        $result = 'Success'
                    }
                    else {
                        $result = 'Unexpected'
                    }
                }
            }
            catch {
                $return = $_.Exception.Message
                $result = 'Error'
            }
        }
        else {
            $return = '(Untarget)'
            $result = 'Skipped'
        }
        New-Object -TypeName PSObject -Property @{
            Index = $i
            Name = $targetTask.Name
            Target = $targetTask.target
            Command = $targetTask.command
            Expected = $targetTask.expect
            Return = $return
            Result = $result
        }
    }
}

function script:Read-Progress
{
    Param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [PSObject]$targetTask
    )
    Process {
        New-Object -TypeName PSObject -Property @{
            Index = $targetTask.Index
            Name = $targetTask.Name
            Target = $targetTask.target
            Command = $targetTask.command
            Expected = $targetTask.expect
            Return = $targetTask.Return
            Result = $targetTask.Result
        }
    }
}

function Invoke-PSCommandSequencer {
    [CmdletBinding()]
    Param (
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [String]$ConfigFile
        ,
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [String[]]$InventoryFiles
        ,
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [String[]]$EnvironmentFiles
        ,
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [String]$ProcedureFile
        ,
        [String]$ProgressFile
        ,
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [String]$PropertySetFile
        ,
        [ValidateScript({Test-Path $_ -PathType Container})]
        [String[]]$ModuleFolders
    )
    Process {
        $ErrorActionPreference = 'Stop'
        $results = @()
        $i = 0
        try {
            Write-Verbose "Loading system configurations."
            if (!($ConfigFile)) {
                foreach($ext in @('psd1', 'json', 'yaml', 'yml')) {
                    if (Test-path ".\conf\System.$ext") {
                        $ConfigFile = ".\conf\System.$ext"
                        break
                    }
                }
            }
            if ($ConfigFile) {
                $configData = Import-DataFile $ConfigFile
            }
            else {
                throw 'Cannot load configuration data.'
            }

            if ($ModuleFolders) {
                Write-Verbose 'Loading module folder(s) by argument.'
                script:Import-ModuleFolder $ModuleFolders -ErrorAction $configData.ModuleFolders.ImportErrorAction
            }
            elseif ($configData.ModuleFolders.Enable) {
                Write-Verbose 'Loading module folder(s) by config file.'
                if ($configData.ModuleFolders.Paths) {
                    script:Import-ModuleFolder $configData.ModuleFolders.Paths -ErrorAction $configData.ModuleFolders.ImportErrorAction
                }
            }
            else {
                Write-Verbose 'Skipped loading modules.'
            }

            if (!($InventoryFiles) -and ($configData.Inventory.Paths)) {
                $InventoryFiles = $configData.Inventory.Paths
            }
            if ($InventoryFiles) {
                $InventoryFiles | ForEach-Object {
                    Write-Verbose "Importing inventory file: $_"
                    $allInventoryData += script:Import-DataFile $_
                }
                $script:InventoryData = $allInventoryData | Where-Object {$_.Name -eq $env:COMPUTERNAME}
                if ($null -ne $script:InventoryData) {
                    Write-Verbose "This computer found in inventry file."
                }
                else {
                    if ($configData.Inventory.ListingRequired) {
                        throw "$env:COMPUTERNAME is not listed in inventory file."
                    }
                }
            }
            elseif ($configData.Inventory.ListingRequired) {
                throw 'Function require listing computer in inventory but file not found.'
            }
            else {
                Write-Verbose 'Skipped loading inventory.'
            }

            if (!($EnvironmentFiles) -and ($configData.Environments.Paths)) {
                $EnvironmentFiles = $configData.Environments.Paths
            }
            if ($EnvironmentFiles) {
                $EnvironmentFiles | ForEach-Object {
                    Write-Verbose "Importing environmentFiles file: $_"
                    $Environments += script:Import-DataFile $_
                }
            }

            if ($ProcedureFile) {
                Write-Verbose 'Loading procedures by argument.'
                $procedureData = script:Import-DataFile $ProcedureFile
            }
            elseif ($configData.Procedures.Path) {
                $ProcedureFile = $configData.Procedures.Path
                if (Test-Path $ProcedureFile) {
                    Write-Verbose 'Loading procedures by config file.'
                    $procedureData = script:Import-DataFile $ProcedureFile
                }
                else {
                    throw 'Procedure file not found.'
                }
            }
            else {
                throw 'Procedure file needed.'
            }

            if ($PropertySetFile) {
                Write-Verbose 'Loading PropertySet file by argument.'
                Update-TypeData $PropertySetFile
            }
            elseif ($configData.Procedures.PropertySet) {
                Write-Verbose 'Loading PropertySet file by config file.'
                $PropertySetFile = $configData.Procedures.PropertySet
                Update-TypeData $PropertySetFile
            }
            else {
                Write-Verbose 'Skipped loading PropertySet file.'
            }

            if ($ProgressFile) {
                Write-Verbose 'Loading ProgressFile by argument.'
            }
            elseif ($configData.Progress.Path) {
                Write-Verbose 'Loading ProgressFile by config file.'
                $ProgressFile = $configData.Progress.Path
            }

            if (Test-Path $ProgressFile) {
                $progressData = script:Import-DataFile $ProgressFile
            }
            else {
                Write-Verbose 'Skipped loading ProgressFile file.'
                $progressData = $null
            } 
        }
        catch {
            throw
        }

        try {
            if ($null -ne $progressData) {
                Write-Verbose 'Detected progress data'
                if ($configData.Progress.Inherit) {
                    Write-Verbose 'Inherit from already executed procedures.'
                    :progressLoop while ($i -lt $progressData.Count) {
                        Write-Progress `
                            -Activity ('Processing (' + ($i+1) + '/' + ($procedureData.Count+1) + ')') `
                            -Status $progressData[$i].Name `
                            -PercentComplete (($i+1) / ($procedureData.Count+1) * 100)
                        switch ($progressData[$i].Result) {
                            'Error' {
                                if ($configData.Progress.RetryError) {
                                    Write-Verbose ("Retrying errored progress: " + $progressData[$i].Name)
                                    $retryProcedure = $true
                                }
                                else {
                                    Write-Verbose ("Skip errored progress: " + $progressData[$i].Name)
                                }
                            }
                            'Unexpected' {
                                if ($configData.Progress.RetryUnexpected) {
                                    Write-Verbose ("Retrying unexpected progress: " + $progressData[$i].Name)
                                    $retryProcedure = $true
                                }
                                else {
                                    Write-Verbose ("Skip unexpected progress: " + $progressData[$i].Name)
                                }
                            }
                            default {
                                Write-Verbose "Skip already succeeded progress."
                            }
                        }
                        if ($retryProcedure) {
                            switch ($configData.Progress.RetryCommandBy) {
                                'procedure' {
                                    $targetTask = $procedureData[$i]
                                }
                                'progress' {
                                    $targetTask = $progressData[$i]
                                }
                            }
                            $result = script:Invoke-Procedure $targetTask
                        }
                        else {
                            $result = script:Read-Progress $progressData[$i]
                        }
                        $result
                        $results += $result
                        Start-Sleep -Milliseconds 100
                        if (
                            ($result.Result -eq 'Error') `
                            -and ($configData.Procedures.ErrorAction -eq 'Stop')
                        ) {
                            $finallyMessage = 'An error occurred.'
                            return
                        }
                        elseif (
                            ($result.Result -eq 'Unexpected') `
                            -and ($configData.Procedures.UnexpectedAction  -eq 'Stop')
                        ) {
                            $finallyMessage = 'An Unexpected Result.'
                            return
                        }
                        switch ($targetTask.PostProcess) {
                            'pause' {
                                Write-Host 'Press Enter to continue...' -ForegroundColor Yellow
                                $null = Read-Host
                            }
                            'reboot' {
                                $finallyMessage = 'Stopping computer...'
                                $restartComputer = $true
                                return
                            }
                            'shutdown' {
                                $finallyMessage = 'Rebooting computer...'
                                $shutComputer = $true
                                return
                            }
                        }
                        $i++
                    }
                }
                else {
                    ForEach-Object -InputObject $progressData {
                        $result = script:Read-Progress $progressData[$_]
                        $result
                        $results += $result
                    }
                    $i = $progressData.Count
                }
            }
            else {
                Write-Verbose 'Progress data does not exist.'
            }

            if ($i -le $procedureData.Count) {
                :procLoop while ($i -lt $procedureData.Count) {
                    $targetTask = $procedureData[$i]
                    Write-Progress `
                        -Activity ('Processing (' + ($i+1) + '/' + ($procedureData.Count+1) + ')') `
                        -Status $targetTask.Name `
                        -PercentComplete (($i+1) / ($procedureData.Count+1) * 100)
                    $result = script:Invoke-Procedure $targetTask
                    $result
                    $results += $result
                    [System.Threading.Thread]::Sleep(300)
                    
                    if (($result.Result -eq 'Error') -and ($configData.Procedures.ErrorAction -eq 'Stop')) {
                        $finallyMessage = "An error occurred."
                        return
                    }
                    elseif (($result.Result -eq 'Unexpected') -and ($configData.Procedures.UnexpectedAction  -eq 'Stop')) {
                        $finallyMessage = "An Unexpected Result."
                        return
                    }
                    switch ($targetTask.PostProcess) {
                        'pause' {
                            Write-Host 'Press Enter to continue...' -ForegroundColor Yellow
                            $null = Read-Host
                        }
                        'reboot' {
                            $finallyMessage = 'Rebooting computer...'
                            $restartComputer = $true
                            return
                        }
                        'shutdown' {
                            $finallyMessage = 'Stopping computer...'
                            $shutComputer = $true
                            return
                        }
                    }
                    $i++
                }
            }
        }
        catch {
            throw
        }
        finally {
            Remove-TypeData -Path $configData.Procedures.PropertySet
            script:Export-DataFile -InputObject $results -Path $configData.Progress.Path
            if ($finallyMessage) {
                Write-Output -InputObject "" > $null
                Write-host $finallyMessage -ForegroundColor 'Yellow'
            }
            if ($shutComputer) {
                Stop-Computer
            }
            elseif($restartComputer) {
                Restart-Computer    
            }
        }
    }
}

Export-ModuleMember -Function Invoke-PSCommandSequencer