param
(
	[object]$Webhookdata
)
#region Functions
function ConvertFrom-VMTagJSON
{
	[CmdletBinding()]
	[OutputType([object])]
	param
	(
		[Parameter(Mandatory = $true,
				   ValueFromPipeline = $true,
				   HelpMessage = 'The Tag where the value is JSON')]
		[ValidateNotNullOrEmpty()]
		[System.String]$JSONTag
	)
	Process
	{
		try
		{
			$JSONTag | ConvertFrom-Json
		}
		Catch
		{
			Write-Error "Unable to convert Tag Input to Object from JSON. Error: $($_.Exception.Message)"
		}
	}
}
function ConvertTo-VMTagJSON
{
	[CmdletBinding()]
	[OutputType([System.String])]
	param
	(
		[Parameter(Mandatory = $true,
				   ValueFromPipeline = $true)]
		[ValidateNotNullOrEmpty()]
		[ValidateScript({
				$Length = $(ConvertTo-Json $_).replace("`r`n", "").Replace(" ", "").Length; if ($length -ge 256) { Throw "Tag value need to be less that 256 characters long, including white spaces etc. Current length $($length)" }
				else { $true }
			})]
		[object]$InputObject
	)
	Process
	{
		try
		{
			$(ConvertTo-Json $InputObject).replace("`r`n", "").Replace(" ", "") # Converts JSON to single line
		}
		Catch
		{
			Write-Error "Unable to convert Tag Input to Object from JSON. Error: $($_.Exception.Message)"
		}
	}
}
#endregion function
Write-Output $webhookdata
if ($WebhookData -ne $null)
{
	# Build out body input to user object object
	$webhookbody = New-Object System.Management.Automation.PSObject
	$propNames = ($WebhookData.RequestBody | Select-String -Pattern '(\w*)(\=)' -AllMatches).Matches | ForEach-Object { $_.Groups[1].value }
	foreach ($a in $propNames)
	{
		$webhookbody | Add-Member -MemberType NoteProperty -Name $a -Value ($WebhookData.RequestBody | Select-String -Pattern "($($a)=)([\w\.%\-$@+]*)").Matches.Groups[2].Value
	}
	$webhookbody | Add-Member -MemberType NoteProperty -Name SubscriptionID -Value ffd616d2-3b41-480e-8619-6974241d43ac
	$webhookbody | Add-Member -MemberType NoteProperty -Name email -Value ""
	$webhookbody.Text
	$webhookbody.response_url = $webhookbody.response_url.replace('%2F', '/').Replace('%3A', ':')
	$webhookbody.Text = $webhookbody.Text.Replace('%3A', ':').Replace('%3B', ';').Replace('+', " ")
}
else
{
	Write-Output "Webhook data empty, breaking"
	break
}
# Vars
$SubscriptionID = Get-AutomationVariable -Name 'SubscriptionID'
# Azure Connection
# Connect to AzureRM
$connection = Get-AutomationConnection -Name AzureRunAsConnection
$null = Connect-AzureRmAccount -ServicePrincipal -Tenant $connection.TenantID `
							   -ApplicationID $connection.ApplicationID -CertificateThumbprint $connection.CertificateThumbprint
# Set the subscription context
if ([System.String]::isNullorEmpty($SubscriptionID) -eq $false)
{
	$null = Set-AzureRmContext -SubscriptionId $SubscriptionID
}
else
{
	Write-Output "Subscription ID empty, breaking"
	break
}
$webhookbody.Text
# Splitting Text input
$TextSplitProps = @{
	'Type'		   = "";
	'Input'	       = '';
	'TimeRange'    = "";
	'HostNames'    = "";
	'ScheduleType' = ""
}
switch -regex ($webhookbody.Text)
{
	'(?i)^\b\d{2}:\d{2}-\d{2}:\d{2}\b$' {
		$script:TextSplitObj = New-Object System.Management.Automation.PSObject -Property $TextSplitProps
		$TextSplitObj.Type = "TimeRange"
		$TextSplitObj.Input = $_
		$TextSplitObj.TimeRange = $_
		break
	}
	'(?i)^\b\w+?-\w+?-\w+?$' {
		$script:TextSplitObj = New-Object System.Management.Automation.PSObject -Property $TextSplitProps
		$TextSplitObj.Type = "HostName"
		$TextSplitObj.Input = $_
		$TextSplitObj.HostNames = $_
		Write-Output $TextSplitObj
		break
	}
	'(?i)^((\b\w+?-\w+?-\w+?;?)+)$' {
		$script:TextSplitObj = New-Object System.Management.Automation.PSObject -Property $TextSplitProps
		$TextSplitObj.Type = "HostNames"
		$TextSplitObj.Input = $_
		$TextSplitObj.HostNames = $_.Split(';')
		break
	}
	'(?i)^(\b\w+?-\w+?-\w+?\b)\s+?(\b\d{2}:\d{2}-\d{2}:\d{2}\b)' {
		$script:TextSplitObj = New-Object System.Management.Automation.PSObject -Property $TextSplitProps
		$TextSplitObj.Type = "HostName and TimeRange"
		$TextSplitObj.Input = $_
		$TextSplitObj.TimeRange = $_.split(' ')[1]
		$TextSplitObj.HostNames = $_.Split(' ')[0]
		break
	}
	'(?i)^((\b\w+?-\w+?-\w+?\b;?)+)\s+?(\b\d{2}:\d{2}-\d{2}:\d{2}\b)' {
		$script:TextSplitObj = New-Object System.Management.Automation.PSObject -Property $TextSplitProps
		$TextSplitObj.Type = "HostNames and TimeRange"
		$TextSplitObj.Input = $_
		$TextSplitObj.TimeRange = $_.split(' ')[1]
		$TextSplitObj.HostNames = $_.Split(' ')[0].Split(';')
		break
	}
	'(?i)^(Weekend)' {
		$script:TextSplitObj = New-Object System.Management.Automation.PSObject -Property $TextSplitProps
		$TextSplitObj.Type = "weekend"
		break
	}
	'(?i)^(Weekday)' {
		$script:TextSplitObj = New-Object System.Management.Automation.PSObject -Property $TextSplitProps
		$TextSplitObj.Type = "weekday"
		break
	}
	'(?i)^(Weekend)\s+?(on|off|schedule)' {
		$script:TextSplitObj = New-Object System.Management.Automation.PSObject -Property $TextSplitProps
		$TextSplitObj.Type = "weekend state"
		$TextSplitObj.ScheduleType = $_.Split(' ')[1]
		break
	}
	'(?i)^(Weekday)\s+?(on|off|schedule)' {
		$script:TextSplitObj = New-Object System.Management.Automation.PSObject -Property $TextSplitProps
		$TextSplitObj.Type = "weekday state"
		$TextSplitObj.ScheduleType = $_.Split(' ')[1]
		break
	}
	'(?i)^(\b\w+?-\w+?-\w+?\b)\s+?(Weekend)' {
		$script:TextSplitObj = New-Object System.Management.Automation.PSObject -Property $TextSplitProps
		$TextSplitObj.Type = "hostname weekend status"
		$TextSplitObj.Input = $_
		$TextSplitObj.HostNames = $_.Split(' ')[0]
		$TextSplitObj.ScheduleType = $_.Split(' ')[2]
		
		break
	}
	'(?i)^(\b\w+?-\w+?-\w+?\b)\s+?(Weekday)' {
		$script:TextSplitObj = New-Object System.Management.Automation.PSObject -Property $TextSplitProps
		$TextSplitObj.Type = "hostname weekday status"
		$TextSplitObj.Input = $_
		$TextSplitObj.HostNames = $_.Split(' ')[0]
		$TextSplitObj.ScheduleType = $_.Split(' ')[2]
		break
	}
	'(?i)^((\b\w+?-\w+?-\w+?\b;?)+)\s+?(Weekend)' {
		$script:TextSplitObj = New-Object System.Management.Automation.PSObject -Property $TextSplitProps
		$TextSplitObj.Type = "hostnames weekend status"
		$TextSplitObj.Input = $_
		$TextSplitObj.HostNames = $_.Split(' ')[0].Split(';')
		$TextSplitObj.ScheduleType = $_.Split(' ')[2]
		
		break
	}
	'(?i)^((\b\w+?-\w+?-\w+?\b;?)+)\s+?(Weekday)' {
		$script:TextSplitObj = New-Object System.Management.Automation.PSObject -Property $TextSplitProps
		$TextSplitObj.Type = "hostnames weekday status"
		$TextSplitObj.Input = $_
		$TextSplitObj.HostNames = $_.Split(' ')[0].Split(';')
		$TextSplitObj.ScheduleType = $_.Split(' ')[2]
		break
	}
	'(?i)^(\b\w+?-\w+?-\w+?\b)\s+?(Weekend)\s+?(on|off|schedule)' {
		$script:TextSplitObj = New-Object System.Management.Automation.PSObject -Property $TextSplitProps
		$TextSplitObj.Type = "hostname weekend"
		$TextSplitObj.Input = $_
		$TextSplitObj.HostNames = $_.Split(' ')[0]
		$TextSplitObj.ScheduleType = $_.Split(' ')[2]
		
		break
	}
	'(?i)^(\b\w+?-\w+?-\w+?\b)\s+?(Weekday)\s+?(on|off|schedule)' {
		$script:TextSplitObj = New-Object System.Management.Automation.PSObject -Property $TextSplitProps
		$TextSplitObj.Type = "hostname weekday"
		$TextSplitObj.Input = $_
		$TextSplitObj.HostNames = $_.Split(' ')[0]
		$TextSplitObj.ScheduleType = $_.Split(' ')[2]
		break
	}
	'(?i)^((\b\w+?-\w+?-\w+?\b;?)+)\s+?(Weekend)\s+?(on|off|schedule)' {
		$script:TextSplitObj = New-Object System.Management.Automation.PSObject -Property $TextSplitProps
		$TextSplitObj.Type = "hostnames weekend"
		$TextSplitObj.Input = $_
		$TextSplitObj.HostNames = $_.Split(' ')[0].Split(';')
		$TextSplitObj.ScheduleType = $_.Split(' ')[2]
		break
	}
	'(?i)^((\b\w+?-\w+?-\w+?\b;?)+)\s+?(Weekday)\s+?(on|off|schedule)' {
		$script:TextSplitObj = New-Object System.Management.Automation.PSObject -Property $TextSplitProps
		$TextSplitObj.Type = "hostnames weekday"
		$TextSplitObj.Input = $_
		$TextSplitObj.HostNames = $_.Split(' ')[0].Split(';')
		$TextSplitObj.ScheduleType = $_.Split(' ')[2]
		break
	}
	'(?i)^(help)' {
		$script:TextSplitObj = New-Object System.Management.Automation.PSObject -Property $TextSplitProps
		$TextSplitObj.Type = "help"
		break
	}
	default
	{
		if ([System.String]::IsNullOrEmpty($_) -eq $false)
		{
			Write-Output "Input from user wasn't formatted correctly: $($webhookbody.Text)"
			$JSON = @{
				"response_type" = "ephemeral";
				"username"	    = "Schedule My VM";
				"text"		    = "Input needs to be formatted like: '09:00-21:00' or 'int-user-nt01 09:00-21:00' or 'int-user-nt01;int-user-cc01 09:00-21:00' or 'int-user-nt01;int-user-cc01' or 'int-user-nt01'";
				"mrkdwn"	    = $true
			}
			Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			break
		}
		else
		{
			Write-Output "No command input from user, running defaults."
		}
	}
}
# Find all VMs owned by user
try
{
	$VMs = Get-AzureRmResource -TagName "int_slack_userid" -TagValue $webhookbody.user_id -ResourceType Microsoft.Compute/virtualMachines -ErrorAction Stop
}
catch
{
	$JSON = @{
		"response_type" = "ephemeral";
		"username"	    = "Schedule My VM";
		"text"		    = "Command Error, contect the systems team.. Try #Systems";
		"mrkdwn"	    = $true
	}
	Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
	break
}
if ([System.String]::IsNullOrEmpty($webhookbody.text))
{
	if ([System.String]::IsNullOrEmpty($VMs))
	{
		$JSON = @{
			"response_type" = "ephemeral";
			"username"	    = "Schedule My VM";
			"text"		    = "Your Slack user isn't registered with any VMs, have you run /VerifyMyVM yet?";
			"mrkdwn"	    = $true
		}
		Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
		break
	}
	else
	{
		$SlackOutput = @"
Here is the list of your VM's and their schedule automation time:`n
"@
		foreach ($a in $VMs)
		{
			$AutomateTags = $a.Tags["int_automate"] | ConvertFrom-VMTagJSON
			Write-Output $AutomateTags
			$SlackOutput += "Your current schedule for VM $($a.Name) is: $($AutomateTags.int_auto_schedule_slot)`n"
		}
		# Response
		$JSON = @{
			"response_type" = "ephemeral";
			"username"	    = "Schedule My VM";
			"text"		    = $SlackOutput;
			"mrkdwn"	    = $true
		}
		Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
	}
}
else
{
	# Switch Jobs
	switch -regex ($TextSplitObj)
	{
		{ $_.Type -eq 'TimeRange' } {
			foreach ($a in $VMs)
			{
				$AutomateTags = $a.Tags["int_automate"] | ConvertFrom-VMTagJSON
				$AutomateTags.int_auto_schedule_slot = $_.TimeRange
				$a.Tags["int_automate"] = $AutomateTags | ConvertTo-VMTagJSON
				$null = Set-AzureRMResource -ResourceName $a.Name -ResourceType "Microsoft.Compute/virtualMachines" -ResourceGroupName $a.ResourceGroupName -Tag $a.Tags -Force -confirm:$false
			}
			$JSON = @{
				"response_type" = "ephemeral";
				"username"	    = "Schedule My VM";
				"text"		    = "Setting all your user VMs schedule to _*$($_.TimeRange)*_";
				"mrkdwn"	    = $true
			}
			Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			break
		}
		{ $_.Type -eq 'Hostname' } {
			$Success = @"
Found the following VMs;`n
"@
			$Successbool = $false
			$OwnerError = @"
You're not an owner or delegate of these VMs:`n
"@
			$OwnerErrorBool = $false
			$FindError = @"
Could not find these VMs:`n
"@
			$FindErrorbool = $false
			
			try
			{
				$VM = Get-AzureRmResource -Name $_.HostNames -ResourceType Microsoft.Compute/virtualMachines -ErrorAction Stop
				if ([System.String]::IsNullOrEmpty($VM) -eq $false)
				{
					if ($VM.Tags["int_slack_userid"] -eq $webhookbody.user_id)
					{
						$AutomateTags = $VM.Tags["int_automate"] | ConvertFrom-VMTagJSON
						$Success += "VM _*$($VM.Name)*_ schedule is $($AutomateTags.int_auto_schedule_slot)`n"
						$Successbool = $true
					}
					else
					{
						$OwnerError += "$($_.HostName)`n"
						$OwnerErrorBool = $true
					}
				}
				else
				{
					$FindError += "$($_.HostNames)`n"
					$FindErrorbool = $true
				}
			}
			catch
			{
				Write-Output "Command Error at HostNames and TimeRange for VM $($_.HostNames)"
			}
			
			# Bulding output
			$FinalForm = @"
The results of your request are below:`n
"@
			if ($Successbool)
			{
				$FinalForm += $Success
			}
			if ($OwnerErrorBool)
			{
				$FinalForm += $OwnerError
			}
			if ($FindErrorbool)
			{
				$FinalForm += $FindError
			}
			$JSON = @{
				"response_type" = "ephemeral";
				"username"	    = "Schedule My VM";
				"text"		    = "$FinalForm";
				"mrkdwn"	    = $true
			}
			Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			break
		}
		{ $_.Type -eq 'HostNames' } {
			$Success = @"
Found the following VMs;`n
"@
			$Successbool = $false
			$OwnerError = @"
You're not an owner or delegate of these VMs:`n
"@
			$OwnerErrorBool = $false
			$FindError = @"
Could not find these VMs:`n
"@
			$FindErrorbool = $false
			foreach ($a in $_.HostNames)
			{
				try
				{
					$VM = Get-AzureRmResource -Name $a -ResourceType Microsoft.Compute/virtualMachines -ErrorAction Stop
					if ([System.String]::IsNullOrEmpty($VM) -eq $false)
					{
						if ($VM.Tags["int_slack_userid"] -eq $webhookbody.user_id)
						{
							$AutomateTags = $VM.Tags["int_automate"] | ConvertFrom-VMTagJSON
							
							$Success += "_*$($VM.Name)*_ is scheduled for $($AutomateTags.int_auto_schedule_slot)`n"
							$Successbool = $true
						}
						else
						{
							$OwnerError += "_*$($a)*_`n"
							$OwnerErrorBool = $true
						}
					}
					else
					{
						$FindError += "_*$($a)*_`n"
						$FindErrorbool = $true
					}
				}
				catch
				{
					Write-Output "Command Error at HostNames and TimeRange for VM $($a)"
				}
			}
			# Bulding output
			$FinalForm = @"
The results of your request are below:`n
"@
			if ($Successbool)
			{
				$FinalForm += $Success
			}
			if ($OwnerErrorBool)
			{
				$FinalForm += $OwnerError
			}
			if ($FindErrorbool)
			{
				$FinalForm += $FindError
			}
			$JSON = @{
				"response_type" = "ephemeral";
				"username"	    = "Schedule My VM";
				"text"		    = "$FinalForm";
				"mrkdwn"	    = $true
			}
			Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			break
		}
		{ $_.Type -eq 'HostName and TimeRange' } {
			$Success = @"
Found and amended the VM;`n
"@
			$Successbool = $false
			$OwnerError = @"
You're not an owner or delegate of the VM:`n
"@
			$OwnerErrorBool = $false
			$FindError = @"
Could not find the VM:`n
"@
			$FindErrorbool = $false
			try
			{
				$VM = Get-AzureRmResource -Name $_.HostNames -ResourceType Microsoft.Compute/virtualMachines -ErrorAction Stop
				if ([System.String]::IsNullOrEmpty($VM) -eq $false)
				{
					if ($VM.Tags["int_slack_userid"] -eq $webhookbody.user_id)
					{
						$AutomateTags = $VM.Tags["int_automate"] | ConvertFrom-VMTagJSON
						$AutomateTags.int_auto_schedule_slot = $_.TimeRange
						$VM.Tags["int_automate"] = $AutomateTags | ConvertTo-VMTagJSON
						$null = Set-AzureRMResource -ResourceName $VM.Name -ResourceType "Microsoft.Compute/virtualMachines" -ResourceGroupName $VM.ResourceGroupName -Tag $VM.Tags -Force -confirm:$false
						$Success += "_*$($VM.Name)*_`n"
						$Successbool = $true
					}
					else
					{
						$OwnerError += "_*$($a)*_`n"
						$OwnerErrorBool = $true
					}
				}
				else
				{
					$FindError += "_*$($a)*_`n"
					$FindErrorbool = $true
				}
			}
			catch
			{
				Write-Output "Command Error at HostNames and TimeRange for VM $($a)"
			}
			# Bulding output
			$FinalForm = @"
The results of your request to change the schedule to _*$($_.TimeRange)*_ for the VM is below:`n
"@
			if ($Successbool)
			{
				$FinalForm += $Success
			}
			if ($OwnerErrorBool)
			{
				$FinalForm += $OwnerError
			}
			if ($FindErrorbool)
			{
				$FinalForm += $FindError
			}
			$JSON = @{
				"response_type" = "ephemeral";
				"username"	    = "Schedule My VM";
				"text"		    = "$FinalForm";
				"mrkdwn"	    = $true
			}
			Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			break
		}
		{ $_.Type -eq 'HostNames and TimeRange' } {
			$Success = @"
Found and amended the following VMs;`n
"@
			$Successbool = $false
			$OwnerError = @"
You're not an owner or delegate of these VMs:`n
"@
			$OwnerErrorBool = $false
			$FindError = @"
Could not find these VMs:`n
"@
			$FindErrorbool = $false
			foreach ($a in $_.HostNames)
			{
				try
				{
					$VM = Get-AzureRmResource -Name $a -ResourceType Microsoft.Compute/virtualMachines -ErrorAction Stop
					if ([System.String]::IsNullOrEmpty($VM) -eq $false)
					{
						if ($VM.Tags["int_slack_userid"] -eq $webhookbody.user_id)
						{
							$AutomateTags = $VM.Tags["int_automate"] | ConvertFrom-VMTagJSON
							$AutomateTags.int_auto_schedule_slot = $_.TimeRange
							$VM.Tags["int_automate"] = $AutomateTags | ConvertTo-VMTagJSON
							$null = Set-AzureRMResource -ResourceName $VM.Name -ResourceType "Microsoft.Compute/virtualMachines" -ResourceGroupName $VM.ResourceGroupName -Tag $VM.Tags -Force -confirm:$false
							$Success += "_*$($VM.Name)*_`n"
							$Successbool = $true
						}
						else
						{
							$OwnerError += "_*$($a)*_`n"
							$OwnerErrorBool = $true
						}
					}
					else
					{
						$FindError += "_*$($a)*_`n"
						$FindErrorbool = $true
					}
				}
				catch
				{
					Write-Output "Command Error at HostNames and TimeRange for VM $($a)"
				}
			}
			# Bulding output
			$FinalForm = @"
The results of your request to change the schedule to _*$($_.TimeRange)*_ for the VMs are below:`n
"@
			if ($Successbool)
			{
				$FinalForm += $Success
			}
			if ($OwnerErrorBool)
			{
				$FinalForm += $OwnerError
			}
			if ($FindErrorbool)
			{
				$FinalForm += $FindError
			}
			$JSON = @{
				"response_type" = "ephemeral";
				"username"	    = "Schedule My VM";
				"text"		    = "$FinalForm";
				"mrkdwn"	    = $true
			}
			Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			break
		}
		{ $_.Type -eq 'weekend' } {
			$Success = @"
Found the following VMs;`n
"@
			foreach ($a in $VMs)
			{
				$AutomateTags = $a.Tags["int_automate"] | ConvertFrom-VMTagJSON
				$Success += "VM _*$($a.Name)*_ schedule type is set to _*$($AutomateTags.int_auto_weekend)*_ over the weekend`n"
			}
			# Bulding output
			$FinalForm = @"
The results of your request are below:`n
"@
			$FinalForm += $Success
			$JSON = @{
				"response_type" = "ephemeral";
				"username"	    = "Schedule My VM";
				"text"		    = "$FinalForm";
				"mrkdwn"	    = $true
			}
			Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			break
		}
		{ $_.Type -eq 'weekday' } {
			$Success = @"
Found the following VMs;`n
"@
			foreach ($a in $VMs)
			{
				$AutomateTags = $a.Tags["int_automate"] | ConvertFrom-VMTagJSON
				$Success += "VM _*$($a.Name)*_ schedule type is set to _*$($AutomateTags.int_auto_weekday)*_ during the week`n"
			}
			# Bulding output
			$FinalForm = @"
The results of your request are below:`n
"@
			$FinalForm += $Success
			$JSON = @{
				"response_type" = "ephemeral";
				"username"	    = "Schedule My VM";
				"text"		    = "$FinalForm";
				"mrkdwn"	    = $true
			}
			Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			break
		}
		{ $_.Type -eq 'help' }	{
			$Help = @"
ScheduleMyVM Usage:
Command Sets

1) /ScheduleMyVM HOSTNAME TIMERANGE
2) /ScheduleMyVM HOSTNAME (Weekday|Weekend) (off|on|schedule)

TIMERANGE
	This needs to be in the format of 09:00-18:00 (no spaces) and in hour increments

HOSTNAME
	The hostname of the VM you want to modify, multiple seperated by a ';' (no space between)
	e.g INT-USER-NT01;INT-USER-CC01

Examples: 

/ScheduleMyVM 08:00-18:00
	
	This Set's all User VMs you're the owner of schedule to start at 08:00 and shutdown at 18:00
______

/ScheduleMyVM INT-USER-NT01 08:00-18:00

	This Set's the user VM INT-USER-NT01 schedule to start at 08:00 and shutdown at 18:00
______

/ScheduleMyVM INT-USER-NT01;INT-USER-CC01 08:00-18:00

	This Set's the user VM INT-USER-NT01 and INT-USER-CC01 schedule to start at 08:00 and shutdown at 18:00
______

/ScheduleMyVM weekend off

	This keeps your user VMs off over the weekends
______

/ScheduleMyVM weekend schedule

	This allows your user VMs to turn on and off over the weekends based on your schedule
______

/ScheduleMyVM INT-USER-NT01 weekday on

	This keeps your user VM INT-USER-01 on over the weekdays
______

/ScheduleMyVM INT-USER-NT01 weekday

	This get the status of the schedule for VM INT-USER-NT01
"@
			$JSON = @{
				"response_type" = "ephemeral";
				"username"	    = "Schedule My VM";
				"text"		    = "$Help";
				"mrkdwn"	    = $true
			}
			Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			break
		}
		{ $_.Type -eq 'weekday state' } {
			$Success = @"
Found and amended the following VMs;`n
"@
			$Successbool = $false
			$OwnerError = @"
You're not an owner or delegate of these VMs:`n
"@
			$OwnerErrorBool = $false
			$FindError = @"
Could not find these VMs:`n
"@
			$FindErrorbool = $false
			foreach ($a in $_.HostNames)
			{
				try
				{
					$VM = Get-AzureRmResource -Name $a -ResourceType Microsoft.Compute/virtualMachines -ErrorAction Stop
					if ([System.String]::IsNullOrEmpty($VM) -eq $false)
					{
						if ($VM.Tags["int_slack_userid"] -eq $webhookbody.user_id)
						{
							$AutomateTags = $VM.Tags["int_automate"] | ConvertFrom-VMTagJSON
							$AutomateTags.int_int_auto_weekday = $_.ScheduleType
							$VM.Tags["int_automate"] = $AutomateTags | ConvertTo-VMTagJSON
							$null = Set-AzureRMResource -ResourceName $VM.Name -ResourceType "Microsoft.Compute/virtualMachines" -ResourceGroupName $VM.ResourceGroupName -Tag $VM.Tags -Force -confirm:$false
							$Success += "_*$($VM.Name)*_`n"
							$Successbool = $true
						}
						else
						{
							$OwnerError += "_*$($a)*_`n"
							$OwnerErrorBool = $true
						}
					}
					else
					{
						$FindError += "_*$($a)*_`n"
						$FindErrorbool = $true
					}
				}
				catch
				{
					Write-Output "Command Error at HostNames and TimeRange for VM $($a)"
				}
			}
			# Bulding output
			$FinalForm = @"
The results of your request to change the weekday schedule to _*$($_.ScheduleType)*_ for the VMs are below:`n
"@
			if ($Successbool)
			{
				$FinalForm += $Success
			}
			if ($OwnerErrorBool)
			{
				$FinalForm += $OwnerError
			}
			if ($FindErrorbool)
			{
				$FinalForm += $FindError
			}
			$JSON = @{
				"response_type" = "ephemeral";
				"username"	    = "Schedule My VM";
				"text"		    = "$FinalForm";
				"mrkdwn"	    = $true
			}
			Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			break
		}
		{ $_.Type -eq 'weekend state' } {
			$Success = @"
Found and amended the following VMs;`n
"@
			$Successbool = $false
			$OwnerError = @"
You're not an owner or delegate of these VMs:`n
"@
			$OwnerErrorBool = $false
			$FindError = @"
Could not find these VMs:`n
"@
			$FindErrorbool = $false
			foreach ($a in $_.HostNames)
			{
				try
				{
					$VM = Get-AzureRmResource -Name $a -ResourceType Microsoft.Compute/virtualMachines -ErrorAction Stop
					if ([System.String]::IsNullOrEmpty($VM) -eq $false)
					{
						if ($VM.Tags["int_slack_userid"] -eq $webhookbody.user_id)
						{
							$AutomateTags = $VM.Tags["int_automate"] | ConvertFrom-VMTagJSON
							$AutomateTags.int_int_auto_weekend = $_.ScheduleType
							$VM.Tags["int_automate"] = $AutomateTags | ConvertTo-VMTagJSON
							$null = Set-AzureRMResource -ResourceName $VM.Name -ResourceType "Microsoft.Compute/virtualMachines" -ResourceGroupName $VM.ResourceGroupName -Tag $VM.Tags -Force -confirm:$false
							$Success += "_*$($VM.Name)*_`n"
							$Successbool = $true
						}
						else
						{
							$OwnerError += "_*$($a)*_`n"
							$OwnerErrorBool = $true
						}
					}
					else
					{
						$FindError += "_*$($a)*_`n"
						$FindErrorbool = $true
					}
				}
				catch
				{
					Write-Output "Command Error at HostNames and TimeRange for VM $($a)"
				}
			}
			# Bulding output
			$FinalForm = @"
The results of your request to change the weekend schedule to _*$($_.ScheduleType)*_ for the VMs are below:`n
"@
			if ($Successbool)
			{
				$FinalForm += $Success
			}
			if ($OwnerErrorBool)
			{
				$FinalForm += $OwnerError
			}
			if ($FindErrorbool)
			{
				$FinalForm += $FindError
			}
			$JSON = @{
				"response_type" = "ephemeral";
				"username"	    = "Schedule My VM";
				"text"		    = "$FinalForm";
				"mrkdwn"	    = $true
			}
			Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			break
		}
		{ $_.Type -eq 'hostname weekend' } {
			$Success = @"
Found and amended the following VMs;`n
"@
			$Successbool = $false
			$OwnerError = @"
You're not an owner or delegate of these VMs:`n
"@
			$OwnerErrorBool = $false
			$FindError = @"
Could not find these VMs:`n
"@
			$FindErrorbool = $false
			
			try
			{
				$VM = Get-AzureRmResource -Name $_.hostnames -ResourceType Microsoft.Compute/virtualMachines -ErrorAction Stop
				if ([System.String]::IsNullOrEmpty($VM) -eq $false)
				{
					if ($VM.Tags["int_slack_userid"] -eq $webhookbody.user_id)
					{
						$AutomateTags = $VM.Tags["int_automate"] | ConvertFrom-VMTagJSON
						$AutomateTags.int_int_auto_weekend = $_.ScheduleType
						$VM.Tags["int_automate"] = $AutomateTags | ConvertTo-VMTagJSON
						$null = Set-AzureRMResource -ResourceName $VM.Name -ResourceType "Microsoft.Compute/virtualMachines" -ResourceGroupName $VM.ResourceGroupName -Tag $VM.Tags -Force -confirm:$false
						$Success += "_*$($VM.Name)*_`n"
						$Successbool = $true
					}
					else
					{
						$OwnerError += "$($_.hostnames)`n"
						$OwnerErrorBool = $true
					}
				}
				else
				{
					$FindError += "$($_.hostnames)`n"
					$FindErrorbool = $true
				}
			}
			catch
			{
				Write-Output "Command Error at HostNames and TimeRange for VM $($_.hostnames)"
			}
			
			# Bulding output
			$FinalForm = @"
The results of your request to change the weekend schedule to _*$($_.ScheduleType)*_ for the VMs are below:`n
"@
			if ($Successbool)
			{
				$FinalForm += $Success
			}
			if ($OwnerErrorBool)
			{
				$FinalForm += $OwnerError
			}
			if ($FindErrorbool)
			{
				$FinalForm += $FindError
			}
			$JSON = @{
				"response_type" = "ephemeral";
				"username"	    = "Schedule My VM";
				"text"		    = "$FinalForm";
				"mrkdwn"	    = $true
			}
			Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			break
		}
		{ $_.Type -eq 'hostname weekday' } {
			$Success = @"
Found and amended the following VMs;`n
"@
			$Successbool = $false
			$OwnerError = @"
You're not an owner or delegate of these VMs:`n
"@
			$OwnerErrorBool = $false
			$FindError = @"
Could not find these VMs:`n
"@
			$FindErrorbool = $false
			
			try
			{
				$VM = Get-AzureRmResource -Name $_.hostnames -ResourceType Microsoft.Compute/virtualMachines -ErrorAction Stop
				if ([System.String]::IsNullOrEmpty($VM) -eq $false)
				{
					if ($VM.Tags["int_slack_userid"] -eq $webhookbody.user_id)
					{
						$AutomateTags = $VM.Tags["int_automate"] | ConvertFrom-VMTagJSON
						$AutomateTags.int_int_auto_weekday = $_.ScheduleType
						$VM.Tags["int_automate"] = $AutomateTags | ConvertTo-VMTagJSON
						$null = Set-AzureRMResource -ResourceName $VM.Name -ResourceType "Microsoft.Compute/virtualMachines" -ResourceGroupName $VM.ResourceGroupName -Tag $VM.Tags -Force -confirm:$false
						$Success += "_*$($VM.Name)*_`n"
						$Successbool = $true
					}
					else
					{
						$OwnerError += "$($_.hostnames)`n"
						$OwnerErrorBool = $true
					}
				}
				else
				{
					$FindError += "$($_.hostnames)`n"
					$FindErrorbool = $true
				}
			}
			catch
			{
				Write-Output "Command Error at HostNames and TimeRange for VM $($_.hostnames)"
			}
			
			# Bulding output
			$FinalForm = @"
The results of your request to change the weekday schedule to _*$($_.ScheduleType)*_ for the VMs are below:`n
"@
			if ($Successbool)
			{
				$FinalForm += $Success
			}
			if ($OwnerErrorBool)
			{
				$FinalForm += $OwnerError
			}
			if ($FindErrorbool)
			{
				$FinalForm += $FindError
			}
			$JSON = @{
				"response_type" = "ephemeral";
				"username"	    = "Schedule My VM";
				"text"		    = "$FinalForm";
				"mrkdwn"	    = $true
			}
			Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			break
		}
		{ $_.Type -eq 'hostnames weekend' } {
			$Success = @"
Found and amended the following VMs;`n
"@
			$Successbool = $false
			$OwnerError = @"
You're not an owner or delegate of these VMs:`n
"@
			$OwnerErrorBool = $false
			$FindError = @"
Could not find these VMs:`n
"@
			$FindErrorbool = $false
			foreach ($a in $_.Hostnames)
			{
				try
				{
					$VM = Get-AzureRmResource -Name $a -ResourceType Microsoft.Compute/virtualMachines -ErrorAction Stop
					if ([System.String]::IsNullOrEmpty($VM) -eq $false)
					{
						if ($VM.Tags["int_slack_userid"] -eq $webhookbody.user_id)
						{
							$AutomateTags = $VM.Tags["int_automate"] | ConvertFrom-VMTagJSON
							$AutomateTags.int_int_auto_weekend = $_.ScheduleType
							$VM.Tags["int_automate"] = $AutomateTags | ConvertTo-VMTagJSON
							$null = Set-AzureRMResource -ResourceName $VM.Name -ResourceType "Microsoft.Compute/virtualMachines" -ResourceGroupName $VM.ResourceGroupName -Tag $VM.Tags -Force -confirm:$false
							$Success += "_*$($VM.Name)*_`n"
							$Successbool = $true
						}
						else
						{
							$OwnerError += "_*$($a)*_`n"
							$OwnerErrorBool = $true
						}
					}
					else
					{
						$FindError += "_*$($a)*_`n"
						$FindErrorbool = $true
					}
				}
				catch
				{
					Write-Output "Command Error at hostnames weekend for VM $($a)"
				}
			}
			# Bulding output
			$FinalForm = @"
The results of your request to change the weekend schedule to _*$($_.ScheduleType)*_ for the VMs are below:`n
"@
			if ($Successbool)
			{
				$FinalForm += $Success
			}
			if ($OwnerErrorBool)
			{
				$FinalForm += $OwnerError
			}
			if ($FindErrorbool)
			{
				$FinalForm += $FindError
			}
			$JSON = @{
				"response_type" = "ephemeral";
				"username"	    = "Schedule My VM";
				"text"		    = "$FinalForm";
				"mrkdwn"	    = $true
			}
			Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			break
		}
		{ $_.Type -eq 'hostnames weekday' } {
			$Success = @"
Found and amended the following VMs;`n
"@
			$Successbool = $false
			$OwnerError = @"
You're not an owner or delegate of these VMs:`n
"@
			$OwnerErrorBool = $false
			$FindError = @"
Could not find these VMs:`n
"@
			$FindErrorbool = $false
			foreach ($a in $_.Hostnames)
			{
				try
				{
					$VM = Get-AzureRmResource -Name $a -ResourceType Microsoft.Compute/virtualMachines -ErrorAction Stop
					if ([System.String]::IsNullOrEmpty($VM) -eq $false)
					{
						if ($VM.Tags["int_slack_userid"] -eq $webhookbody.user_id)
						{
							$AutomateTags = $VM.Tags["int_automate"] | ConvertFrom-VMTagJSON
							$AutomateTags.int_int_auto_weekday = $_.ScheduleType
							$VM.Tags["int_automate"] = $AutomateTags | ConvertTo-VMTagJSON
							$null = Set-AzureRMResource -ResourceName $VM.Name -ResourceType "Microsoft.Compute/virtualMachines" -ResourceGroupName $VM.ResourceGroupName -Tag $VM.Tags -Force -confirm:$false
							$Success += "_*$($VM.Name)*_`n"
							$Successbool = $true
						}
						else
						{
							$OwnerError += "_*$($a)*_`n"
							$OwnerErrorBool = $true
						}
					}
					else
					{
						$FindError += "_*$($a)*_`n"
						$FindErrorbool = $true
					}
				}
				catch
				{
					Write-Output "Command Error at hostnames weekend for VM $($a)"
				}
			}
			# Bulding output
			$FinalForm = @"
The results of your request to change the weekday schedule to _*$($_.ScheduleType)*_ for the VMs are below:`n
"@
			if ($Successbool)
			{
				$FinalForm += $Success
			}
			if ($OwnerErrorBool)
			{
				$FinalForm += $OwnerError
			}
			if ($FindErrorbool)
			{
				$FinalForm += $FindError
			}
			$JSON = @{
				"response_type" = "ephemeral";
				"username"	    = "Schedule My VM";
				"text"		    = "$FinalForm";
				"mrkdwn"	    = $true
			}
			Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			break
		}
		{ $_.Type -eq 'hostname weekday status' } {
			$Success = @"
Found the following VMs;`n
"@
			$Successbool = $false
			$OwnerError = @"
You're not an owner or delegate of these VMs:`n
"@
			$OwnerErrorBool = $false
			$FindError = @"
Could not find these VMs:`n
"@
			$FindErrorbool = $false
			
			try
			{
				$VM = Get-AzureRmResource -Name $_.hostnames -ResourceType Microsoft.Compute/virtualMachines -ErrorAction Stop
				if ([System.String]::IsNullOrEmpty($VM) -eq $false)
				{
					if ($VM.Tags["int_slack_userid"] -eq $webhookbody.user_id)
					{
						$AutomateTags = $VM.Tags["int_automate"] | ConvertFrom-VMTagJSON
						$Success += "VM _*$($VM.Name)*_ is set to _*$($AutomateTags.int_auto_weekday)*_ during the week.`n"
						$Successbool = $true
					}
					else
					{
						$OwnerError += "$($_.hostnames)`n"
						$OwnerErrorBool = $true
					}
				}
				else
				{
					$FindError += "$($_.hostnames)`n"
					$FindErrorbool = $true
				}
			}
			catch
			{
				Write-Output "Command Error at Hostname weekday status for VM $($_.hostnames)"
			}
			
			# Bulding output
			$FinalForm = @"
The results of your request are below:`n
"@
			if ($Successbool)
			{
				$FinalForm += $Success
			}
			if ($OwnerErrorBool)
			{
				$FinalForm += $OwnerError
			}
			if ($FindErrorbool)
			{
				$FinalForm += $FindError
			}
			$JSON = @{
				"response_type" = "ephemeral";
				"username"	    = "Schedule My VM";
				"text"		    = "$FinalForm";
				"mrkdwn"	    = $true
			}
			Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			break
		}
		{ $_.Type -eq 'hostname weekend status' } {
			$Success = @"
Found the following VMs;`n
"@
			$Successbool = $false
			$OwnerError = @"
You're not an owner or delegate of these VMs:`n
"@
			$OwnerErrorBool = $false
			$FindError = @"
Could not find these VMs:`n
"@
			$FindErrorbool = $false
			
			try
			{
				$VM = Get-AzureRmResource -Name $_.hostnames -ResourceType Microsoft.Compute/virtualMachines -ErrorAction Stop
				if ([System.String]::IsNullOrEmpty($VM) -eq $false)
				{
					if ($VM.Tags["int_slack_userid"] -eq $webhookbody.user_id)
					{
						$AutomateTags = $VM.Tags["int_automate"] | ConvertFrom-VMTagJSON
						$Success += "VM _*$($VM.Name)*_ is set to _*$($AutomateTags.int_auto_weekend)*_ at the weekend.`n"
						$Successbool = $true
					}
					else
					{
						$OwnerError += "$($_.hostnames)`n"
						$OwnerErrorBool = $true
					}
				}
				else
				{
					$FindError += "$($_.hostnames)`n"
					$FindErrorbool = $true
				}
			}
			catch
			{
				Write-Output "Command Error at HostNames and TimeRange for VM $($_.hostnames)"
			}
			
			# Bulding output
			$FinalForm = @"
The results of your request are below:`n
"@
			if ($Successbool)
			{
				$FinalForm += $Success
			}
			if ($OwnerErrorBool)
			{
				$FinalForm += $OwnerError
			}
			if ($FindErrorbool)
			{
				$FinalForm += $FindError
			}
			$JSON = @{
				"response_type" = "ephemeral";
				"username"	    = "Schedule My VM";
				"text"		    = "$FinalForm";
				"mrkdwn"	    = $true
			}
			Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			break
		}
		{ $_.Type -eq 'hostnames weekday status' } {
			$Success = @"
Found the following VMs;`n
"@
			$Successbool = $false
			$OwnerError = @"
You're not an owner or delegate of these VMs:`n
"@
			$OwnerErrorBool = $false
			$FindError = @"
Could not find these VMs:`n
"@
			$FindErrorbool = $false
			foreach ($a in $_.Hostnames)
			{
				try
				{
					$VM = Get-AzureRmResource -Name $a -ResourceType Microsoft.Compute/virtualMachines -ErrorAction Stop
					if ([System.String]::IsNullOrEmpty($VM) -eq $false)
					{
						if ($VM.Tags["int_slack_userid"] -eq $webhookbody.user_id)
						{
							$AutomateTags = $VM.Tags["int_automate"] | ConvertFrom-VMTagJSON
							$Success += "VM _*$($VM.Name)*_ is set to _*$($AutomateTags.int_auto_weekday)*_ during the week.`n"
							$Successbool = $true
						}
						else
						{
							$OwnerError += "_*$($a)*_`n"
							$OwnerErrorBool = $true
						}
					}
					else
					{
						$FindError += "_*$($a)*_`n"
						$FindErrorbool = $true
					}
				}
				catch
				{
					Write-Output "Command Error at hostnames weekend for VM $($a)"
				}
			}
			# Bulding output
			$FinalForm = @"
The results of your request to change the weekend schedule to _*$($_.ScheduleType)*_ for the VMs are below:`n
"@
			if ($Successbool)
			{
				$FinalForm += $Success
			}
			if ($OwnerErrorBool)
			{
				$FinalForm += $OwnerError
			}
			if ($FindErrorbool)
			{
				$FinalForm += $FindError
			}
			$JSON = @{
				"response_type" = "ephemeral";
				"username"	    = "Schedule My VM";
				"text"		    = "$FinalForm";
				"mrkdwn"	    = $true
			}
			Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			break
		}
		{ $_.Type -eq 'hostnames weekend status' } {
			$Success = @"
Found the following VMs;`n
"@
			$Successbool = $false
			$OwnerError = @"
You're not an owner or delegate of these VMs:`n
"@
			$OwnerErrorBool = $false
			$FindError = @"
Could not find these VMs:`n
"@
			$FindErrorbool = $false
			foreach ($a in $_.Hostnames)
			{
				try
				{
					$VM = Get-AzureRmResource -Name $a -ResourceType Microsoft.Compute/virtualMachines -ErrorAction Stop
					if ([System.String]::IsNullOrEmpty($VM) -eq $false)
					{
						if ($VM.Tags["int_slack_userid"] -eq $webhookbody.user_id)
						{
							$AutomateTags = $VM.Tags["int_automate"] | ConvertFrom-VMTagJSON
							$Success += "VM _*$($VM.Name)*_ is set to _*$($AutomateTags.int_auto_weekend)*_ at the weekend.`n"
							$Successbool = $true
						}
						else
						{
							$OwnerError += "_*$($a)*_`n"
							$OwnerErrorBool = $true
						}
					}
					else
					{
						$FindError += "_*$($a)*_`n"
						$FindErrorbool = $true
					}
				}
				catch
				{
					Write-Output "Command Error at hostnames weekend for VM $($a)"
				}
			}
			# Bulding output
			$FinalForm = @"
The results of your request to change the weekend schedule to _*$($_.ScheduleType)*_ for the VMs are below:`n
"@
			if ($Successbool)
			{
				$FinalForm += $Success
			}
			if ($OwnerErrorBool)
			{
				$FinalForm += $OwnerError
			}
			if ($FindErrorbool)
			{
				$FinalForm += $FindError
			}
			$JSON = @{
				"response_type" = "ephemeral";
				"username"	    = "Schedule My VM";
				"text"		    = "$FinalForm";
				"mrkdwn"	    = $true
			}
			Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			break
		}
		Default
		{
		}
	}
}