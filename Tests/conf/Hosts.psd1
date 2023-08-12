@(
    @{
        Name = 'PC-001'
        Type = 'Sales'
        IPAddress = '192.168.10.1'
        SubnetMask = '255.255.255.0'
        DefaultGateWay = '192.168.10.254'
        DNS = '192.168.0.100', '192.168.0.101'
        JoinDomain = $true
        JoinOU = 'Sales'
        Role = 'AnsibleHost'
    }
    @{
        Name = 'PC-002'
        Type = 'Development'
        IPAddress = '192.168.20.1'
        SubnetMask = '255.255.255.0'
        DefaultGateWay = '192.168.20.254'
        DNS = '192.168.0.100', '192.168.0.101'
        JoinDomain = $false
    }
)