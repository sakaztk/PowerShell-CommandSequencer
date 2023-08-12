@(
    @{
        name = 'Check logon user'
        target = 'all'
        command = 'whoami.exe'
        expect = 'sakoda\kazutaka'
    }
    @{
        name = 'SerialNumber'
        target = 'all'
        command = '(Get-CimInstance Win32_BIOS).SerialNumber'
    }
    @{
        name = 'Ping to loopback'
        target =  'all'
        command =  'ping 127.1 >$null; $LASTEXITCODE'
        expect =  0
        PostProcess = 'Pause'
    }
    @{
        name = 'Ping to Domain'
        target = 'all'
        command = 'ping $Environments.DomainName >$null; $LASTEXITCODE'
        expect =  0
    }
)
