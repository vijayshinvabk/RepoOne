param(
	[string]$WebServers   # a space-separated list of server names
	)

function Write-Log
{
    try
    {
        $msg = $Args -join ' '
        $lineprefix = '{0:u}: ' -f (Get-Date)
        $msg = $msg -replace '(?m)^', $lineprefix
        $msg >> "$(Get-BrewmasterLogsFolder)\WebDeploySyncContent.log"
        Write-Output $msg
    }
    catch
    {
        Write-Warning "Write-Log failed: $_"
    }
}

try
{
    $syncpath = 'C:\Inetpub\wwwroot'
    Write-Log ''
    Write-Log Synchronizing $syncpath
    $publishingServer = $env:computername
    foreach ($server in ((-split $WebServers) -ne $publishingServer))
    { 
        $exe = "$env:ProgramFiles\IIS\Microsoft Web Deploy V3\msdeploy.exe"
        $arguments = @("-verb:sync", "-source:contentPath=$syncpath,computerName=$publishingServer", "-dest:contentPath=$syncpath,computerName=$server")
        Write-Log Launching $exe "$arguments"
        & $exe $arguments 2>&1 | % { 
            if ($_ -is [System.Management.Automation.ErrorRecord]) { 
                Write-Log ($_ | Format-List -Force | out-string)
            }
            else {
                Write-Log $_
            }
        }
    }
    Write-Log Synchronization complete.
}
catch
{
    Write-Log Synchronization failed:
    Write-Log ($_ | Format-List * -Force | Out-String).Trim()
    throw
}
