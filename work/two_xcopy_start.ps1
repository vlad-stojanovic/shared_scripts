[string]$sqlServerSource = Join-Path -Path $env:BUILD_OUTPUT_ROOT -ChildPath "sqlservr"
If (-Not (Test-Path -Path $sqlServerSource -PathType Container)) {
    Log Error "No SQL source files found @ [$($sqlServerSource)]"
    return
}

[string]$sqlServersRootPath = "D:\Temp"
[HashTable[]]$sqlServers = @(
    , @{ path = "$($sqlServersRootPath)\SqlServr1"; port = 1443; instance = 5; }
    , @{ path = "$($sqlServersRootPath)\SqlServr2"; port = 1447; instance = 7; }
)

$sqlServers |
    Where-Object { -Not [string]::IsNullOrWhiteSpace($_.path) } |
    ForEach-Object {
        If (Test-Path -Path $_.path) {
            Remove-Item -Recurse -Force $_.path
        }

        Log Info "Copying SQL source -> [$($_.path)]"
        Copy-Item -Recurse -Path $sqlServerSource -Destination $_.path
        Log Info "Starting SQL server from [$($_.path)]"
        Invoke-Expression "$($_.path)\sqlservr.cmd -instancenum $($_.instance) -registry service"
        Invoke-Expression -Command "$($env:OSQL_PATH) -b -S.,$($_.port) -E -Q `"EXEC sp_addsrvrolemember '$($env:USERDOMAIN)\$($env:USERNAME)', 'sysadmin'`""
    }

check_for_sql_processes -expected 'Many processes'

reset_testshell_environment_variables -envType "XCopy" -customEnvFilePath "$($env:ENVIRONMENT_FOLDER)\$(get_build_configuration_folder)\environment_xcopy_two_instances.xml"
