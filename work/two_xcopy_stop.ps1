[string]$sqlServersRootPath = "D:\Temp"
[HashTable[]]$sqlServers = @(
    , @{ path = "$($sqlServersRootPath)\SqlServr1"; port = 1443; instance = 5; }
    , @{ path = "$($sqlServersRootPath)\SqlServr2"; port = 1447; instance = 7; }
)

$sqlServers |
    Where-Object { -Not [string]::IsNullOrWhiteSpace($_.path) } |
    ForEach-Object {
        If (-Not (Test-Path -Path $_.path -PathType Container)) {
            Log Warning "SQL server directory [$($_.path)] not found"
            return
        }

        Log Info "Stopping SQL server from directory [$($_.path)]"
        Invoke-Expression "$($_.path)\sqlservr.cmd -instancenum $($_.instance) -registry remove"
        Remove-Item -Recurse -Force $_.path -ErrorAction Ignore    
    }

check_for_sql_processes -expected None

reset_testshell_environment_variables
