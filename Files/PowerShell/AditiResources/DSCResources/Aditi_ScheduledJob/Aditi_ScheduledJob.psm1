<#
# Based on the ScheduledTask_StackExchange resource written by Steven Murawski.
# See https://github.com/PowerShellOrg/DSC.
#>

function Get-TargetResource
{
    [OutputType([Hashtable])]
    param (
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name,
        
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $FilePath,

        [parameter()]
        [string]
        $At = (Get-Date),

        [parameter()]
        [int]
        $Hours = 0,

        [parameter()]
        [int]
        $Minutes = 0,
        
        [parameter()]        
        [bool]
        $Once = $false,

        [parameter()]
        [int]
        $DaysInterval,
        
        [parameter()]        
        [bool]
        $Daily = $false,
        
        [parameter()]        
        [string[]]
        $DaysOfWeek,

        [parameter()]        
        [bool]
        $Weekly = $false,

        [parameter()]
        [System.Management.Automation.PSCredential]
        $Credential = [System.Management.Automation.PSCredential]::Empty,

        [ValidateSet('Present','Absent')]
        [string]
        $Ensure = 'Present'
    )
    
    $icmArgs = @{}
    if ($Credential)
    {
        #$icmArgs.Session = new-pssession -computername $env:COMPUTERNAME -Credential $Credential -Authentication CredSSP
        $icmArgs.ComputerName = "."
        $icmArgs.Credential = $Credential
    }
    $Job = Invoke-Command @icmArgs { Get-ScheduledJob -Name $using:Name -ErrorAction SilentlyContinue }

    #Needs to return a hashtable that returns the current
    #status of the configuration component

    $Configuration = @{
        Name = $Name    
    }
    if ($Job)
    {
        $Configuration.FilePath = $Job.Command
        if ($Job.JobTriggers[0].At.HasValue)
        {
            $Configuration.At = $job.JobTriggers[0].At.Value.ToString()
        }
        if ($Job.JobTriggers[0].RepetitionInterval.HasValue)
        {           
            $Configuration.Hours = $Job.JobTriggers[0].RepetitionInterval.Value.Hours
            $Configuration.Minutes = $Job.JobTriggers[0].RepetitionInterval.Value.Minutes
        }
        
        if ( 'Once' -like $Job.JobTriggers[0].Frequency )
        {
            $Configuration.Once = $true
        }
        else
        {
            $Configuration.Once = $false
        }
        if ( 'Daily' -like $Job.JobTriggers[0].Frequency )
        {
            $Configuration.Daily = $true
            $Configuration.DaysInterval = $Job.JobTriggers[0].Interval
        }
        else
        {
            $Configuration.Daily = $false            
        }
        if ( 'Weekly' -like $Job.JobTriggers[0].Frequency )
        {
            $Configuration.Weekly = $true
            [string[]]$Configuration.DaysOfWeek = $job.JobTriggers[0].DaysOfWeek
        }
        else
        {
            $Configuration.Weekly = $false            
        }

        $Configuration.Credential = $job.Credential
        $Configuration.Ensure = 'Present'
    }
    else
    {
        $Configuration.Ensure = 'Absent'
    }

    return $Configuration
}

function Set-TargetResource
{
    param (
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name,
        
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $FilePath,

        [parameter()]
        [string]
        $At = (Get-Date),

        [parameter()]
        [int]
        $Hours = 0,

        [parameter()]
        [int]
        $Minutes = 0,
        
        [parameter()]        
        [bool]
        $Once = $false,

        [parameter()]
        [int]
        $DaysInterval = 0,
        
        [parameter()]        
        [bool]
        $Daily = $false,
        
        [parameter()]        
        [string[]]
        $DaysOfWeek,

        [parameter()]        
        [bool]
        $Weekly = $false,

        [parameter()]
        [System.Management.Automation.PSCredential]
        $Credential = [System.Management.Automation.PSCredential]::Empty,

        [ValidateSet('Present','Absent')]
        [string]
        $Ensure = 'Present'
    )

    $icmArgs = @{}
    if ($Credential)
    {
        #$icmArgs.Session = new-pssession -computername $env:COMPUTERNAME -Credential $Credential -Authentication CredSSP
        $icmArgs.ComputerName = "."
        $icmArgs.Credential = $Credential
    }
    
    if ($Ensure -like 'Present')
    {
        $JobTriggerParameters = @{}
        $JobTriggerParameters.At = $At 
        if ($Once)
        {
            $JobTriggerParameters.Once = $true          
            if (($Hours -gt 0) -or ($Minutes -gt 0))
            {
                $JobTriggerParameters.RepetitionInterval = New-TimeSpan -Hours $Hours -Minutes $Minutes
                $JobTriggerParameters.RepetitionDuration = [timespan]::MaxValue
            }
        }
        elseif ($Daily)
        {
            $JobTriggerParameters.Daily = $true    
            if ($DaysInterval -gt 0)
            {
                $JobTriggerParameters.DaysInterval = $DaysInterval
            }
        }
        elseif ($Weekly)
        {
            $JobTriggerParameters.Weekly = $true
            if ($DaysOfWeek.count -gt 0)
            {
                $JobTriggerParameters.DaysOfWeek = $DaysOfWeek
            }
        }
        
        $JobOptions = @{
            MultipleInstancePolicy = 'IgnoreNew'
        }
        
        Invoke-Command @icmArgs -ArgumentList $JobTriggerParameters,$JobOptions `
        {
            param($JobTriggerParameters, $JobOptions)
			
			$cred = $using:Credential

            $JobParameters = @{
                Name = $using:Name
                FilePath = $using:FilePath        
                MaxResultCount = 10
                Trigger = New-JobTrigger @JobTriggerParameters
                ScheduledJobOption = New-ScheduledJobOption @JobOptions
            }
            if ($cred)
            {
				#hack to make sure that password logon is used
				$password = ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($cred.Password)))
                $userName = $cred.GetNetworkCredential().UserName
                
                $JobParameters["Credential"] = (New-Object System.Management.Automation.PSCredential($userName, (ConvertTo-SecureString $password -AsPlainText -Force)))
            }

            $Job = Get-ScheduledJob -Name $using:Name -ErrorAction SilentlyContinue
            if ($Job)
            {
                $job | Unregister-ScheduledJob -Force -Confirm:$False
            }

            Register-ScheduledJob @JobParameters
        }
    }
    else
    {
        Invoke-Command @icmArgs `
        {
            $Job = Get-ScheduledJob -Name $using:Name -ErrorAction SilentlyContinue
            if ($Job)
            {
                $job | Unregister-ScheduledJob -Force -Confirm:$False
            }
        }
    }
}

function Test-TargetResource
{
    [OutputType([boolean])]
    param (
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name,
        
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $FilePath,

        [parameter()]
        [string]
        $At = (Get-Date),

        [parameter()]
        [int]
        $Hours = 0,

        [parameter()]
        [int]
        $Minutes = 0,
        
        [parameter()]        
        [bool]
        $Once = $false,

        [parameter()]
        [int]
        $DaysInterval,
        
        [parameter()]        
        [bool]
        $Daily = $false,
        
        [parameter()]        
        [string[]]
        $DaysOfWeek,

        [parameter()]        
        [bool]
        $Weekly = $false,

        [parameter()]
        [System.Management.Automation.PSCredential]
        $Credential = [System.Management.Automation.PSCredential]::Empty,

        [ValidateSet('Present','Absent')]
        [string]
        $Ensure = 'Present'
    )

    $IsValid = $true
    
    $icmArgs = @{}
    if ($Credential)
    {
        #$icmArgs.Session = new-pssession -computername $env:COMPUTERNAME -Credential $Credential -Authentication CredSSP
        $icmArgs.ComputerName = "."
        $icmArgs.Credential = $Credential
    }
    $Job = Invoke-Command @icmArgs { Get-ScheduledJob -Name $using:Name -ErrorAction SilentlyContinue }

    if ($Ensure -like 'Present')
    {
        if ($Job)
        {
            $IsValid = $IsValid -and ( $FilePath -like $Job.Command )
            Write-Verbose "Checking Filepath against existing command.  Status is $IsValid."

            $IsValid = $IsValid -and (Test-JobTriggerAtTime -Trigger $job.JobTriggers[0] -At $At)
            Write-Verbose "Checking Job Trigger At time.  Status is $IsValid."
            
            $IsValid = $IsValid -and (Test-OnceJobTrigger -Trigger $job.JobTriggers[0] -Hours $Hours -Minutes $Minutes -Once $Once)
            Write-Verbose "Checking Job Trigger repetition is set to Once.  Status is $IsValid."

            $IsValid = $IsValid -and (Test-DailyJobTrigger -Trigger $Job.JobTriggers[0] -Interval $DaysInterval -Daily $Daily)            
            Write-Verbose "Checking Job Trigger repetition is set to Daily.  Status is $IsValid."
            
            $IsValid = $IsValid -and (Test-WeeklyJobTrigger -Trigger $Job.JobTriggers[0] -DaysOfWeek $DaysOfWeek -Weekly $Weekly)            
            Write-Verbose "Checking Job Trigger repetition is set to Weekly.  Status is $IsValid."            

            $IsValid = $IsValid -and (Test-JobCredential -Job $job -Credential $Credential)
            Write-Verbose "Checking Job credential.  Status is $IsValid."
        }
        else
        {
            $IsValid = $false
            Write-Verbose "Unable to find matching job."
        }
    }
    else
    {
        if ($job)
        {
            $IsValid = $false
            Write-Verbose "Job should not be present, but is registered."
        }
        else
        {
            Write-Verbose "No job found and no job should be present."
        }
    }


    return $IsValid
}

function Test-JobCredential
{
    param (
        $Job,
        [pscredential]
        $Credential
    )  
      
    $IsValid = Compare-Credential $Credential $Job.Credential
    return $IsValid
}

function Compare-Credential
{
    [OutputType([bool])]
    param (
        [pscredential]
        $Credential1,
        [pscredential]
        $Credential2
    )  
      
    $IsEqual = ( $Credential1 -eq $Credential2 )
    if (!$IsEqual -and $Credential1 -and $Credential2)
    {
        $IsEqual = ( $Credential1.UserName -eq $Credential2.UserName ) -and 
                   ( Compare-SecureString $Credential1.Password $Credential2.Password )
    }
    return $IsEqual
}

function Compare-SecureString
{
    [OutputType([bool])]
    param (
        [System.Security.SecureString]
        $Value1,
        [System.Security.SecureString]
        $Value2
    )  

    function Decrypt-SecureString
    {
        [OutputType([byte[]])]
        param(
            [Parameter(ValueFromPipeline=$true,Mandatory=$true,Position=0)]
            [System.Security.SecureString]
            $SecureString
        )

        $marshal = [System.Runtime.InteropServices.Marshal]
        $ptr = $marshal::SecureStringToGlobalAllocUnicode( $SecureString )
        $array = new-object byte[] ($SecureString.Length * 2)
        $marshal::Copy($ptr, $array, 0, $array.Length)
        $marshal::ZeroFreeGlobalAllocUnicode( $ptr )
        return $array
    }
    
    $IsEqual = ( $Value1 -eq $Value2 )
    if (!$IsEqual -and $Value1 -and $Value2)
    {
        $bytes1 = Decrypt-SecureString $Value1
        $bytes2 = Decrypt-SecureString $Value2
        $IsEqual = ($bytes1.Length -eq $bytes2.Length)
        for ($i = 0; $IsEqual -and $i -lt $bytes1.Length; $i++)
        {
            $IsEqual = ($bytes1[$i] -eq $bytes2[$i])
        }
        # erase the decrypted memory
        [array]::Clear($bytes1, 0, $bytes1.Length)
        [array]::Clear($bytes2, 0, $bytes2.Length)
    }
    return $IsEqual
}

function Test-JobTriggerAtTime
{
    param (
        $Trigger,
        [string]
        $At
    )  
      
    $IsValid = $Trigger.At.HasValue
    if ($IsValid)
    {
        $IsValid = $IsValid -and ( [datetime]::Parse($At) -eq $Trigger.At.Value )                
    }
    return $IsValid
}

function Test-WeeklyJobTrigger
{
    param 
    (
        $Trigger,
        [string[]]
        $DaysOfWeek,
        [bool]
        $Weekly 
    )

    $IsValid = $true
    if ( $Weekly )    
    {
        $IsValid = $IsValid -and ( 'Weekly' -like $Trigger.Frequency )
        $IsValid = $IsValid -and ( $DaysOfWeek.Count -eq $Trigger.DaysOfWeek.count )
        if ($IsValid -and ($DaysOfWeek.count -gt 0))
        {
            foreach ($day in $Trigger.DaysOfWeek)
            {
                $IsValid = $IsValid -and ($DaysOfWeek -contains $day)
            }
        }                
    }
    else
    {
        $IsValid = $IsValid -and ( 'Weekly' -notlike $Trigger.Frequency )
    }
    return $IsValid
}

function Test-DailyJobTrigger
{
    param (
        $Trigger,
        [int]
        $DaysInterval,
        [bool]
        $Daily
    )

    $IsValid = $true
    if ( $Daily )
    {
        $IsValid = $IsValid -and ( 'Daily' -like $Trigger.Frequency )
        $IsValid = $IsValid -and ( $DaysInterval -eq $Trigger.Interval )
    }
    else
    {
        $IsValid = $IsValid -and ( 'Daily' -notlike $Trigger.Frequency )
    }
    return $IsValid
}

function Test-OnceJobTrigger
{
    param (
        $Trigger,
        [int]
        $Hours,
        [int]
        $Minutes,
        [bool]
        $Once
    )

    $IsValid = $true
    if ($Once)
    {
        $IsValid = $IsValid -and ( 'Once' -like $Trigger.Frequency )
        $IsValid = $IsValid -and $Trigger.RepetitionInterval.HasValue
        
        if ($IsValid)
        {           
            $IsValid = $IsValid -and ( $Hours -eq $Trigger.RepetitionInterval.Value.Hours )
            $IsValid = $IsValid -and ( $Minutes -eq $Trigger.RepetitionInterval.Value.Minutes )            
        }        
        Write-Verbose "Checking Job Trigger repetition interval.  Status is $IsValid."
    }
    else
    {
        $IsValid = $IsValid -and ( 'Once' -notlike $Trigger.Frequency )
    }
    return $IsValid
}
