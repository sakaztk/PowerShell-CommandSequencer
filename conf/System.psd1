@{
    Inventory = @{
        Paths = '.\conf\hosts.psd1'
        ListingRequired = $false
    }
    Procedures = @{
        Path = '.\conf\Procedures.yaml'
        ErrorAction = 'stop'
        UnexpectedAction = 'continue'
        PropertySet = '.\conf\PropertySet.ps1xml'
    }
    Progress = @{
        Path = '.\conf\progress.json' #xml/json/yaml
        Inherit = $true
        RetryError = $true
        RetryUnexpected = $true
        RetryCommandBy = 'Procedure' #Procedure/Progress
    }
    Environments = @{
        Enable = $true
        Paths = '.\conf\environments.psd1'
    }
    ModuleFolders = @{
        Enable = $false
        ImportErrorAction = 'SilentlyContinue'
        Paths = '.\Modules'
    }
}
