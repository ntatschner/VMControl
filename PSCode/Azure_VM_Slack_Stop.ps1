# Input Parameters
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

if ($WebhookData -ne $null)
{
	$webrequestCheck = ConvertFrom-Json $Webhookdata.RequestBody
	$webrequestCheck.requestbody
	if ($webrequestCheck.RequestBody -like "*token=*team_id=*")
	{
		# Build out body input to user object object
		$webhookbody = New-Object System.Management.Automation.PSObject
		$propNames = ($(ConvertFrom-Json $WebhookData.RequestBody).RequestBody | Select-String -Pattern '(\w*)(\=)' -AllMatches).Matches | % { $_.Groups[1].value }
		foreach ($a in $propNames)
		{
			$webhookbody | Add-Member -MemberType NoteProperty -Name $a -Value ($(ConvertFrom-Json $WebhookData.RequestBody).RequestBody | Select-String -Pattern "($($a)=)([a-zA-Z0-9\.%$@-]*)").Matches.Groups[2].Value
		}
		$webhookbody | Add-Member -MemberType NoteProperty -Name SubscriptionID -Value $(ConvertFrom-Json $WebhookData.RequestBody).SubscriptionID
		$webhookbody | Add-Member -MemberType NoteProperty -Name email -Value ""
		$webhookbody.response_url = $webhookbody.response_url.replace('%2F', '/').Replace('%3A', ':')
		$webhookbody.Text = $webhookbody.text.replace('%3B', ';')
	}
	else
	{
		$webhookbody = convertfrom-json $webhookdata.RequestBody
	}
	Write-Output "Webhook data;"
	$webhookbody | Write-Output
}
else
{
	Write-Output "Webhook data empty, breaking"
	break
}
# Vars 

$SubscriptionID = Get-AutomationVariable -Name 'SubscriptionID'
$emailAddress = $webhookbody.email

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

# Checking Webhook and modify depending on source
if ([System.String]::IsNullOrEmpty($webhookbody.user_id) -eq $false)
{
	# Find VMs specified
	
	$VMs = @()
	
	foreach ($a in $webhookbody.text.Split(';'))
	{
		$Test = Get-AzureRmResource -Name $a.Trim() -ResourceType Microsoft.Compute/virtualMachines
		if ([System.String]::IsNullOrEmpty($Test) -eq $false)
		{
			$VMs += $Test
		}
		else
		{
			$JSON = @{
				"response_type" = "ephemeral";
				"username"	    = "Stop My VM";
				"text"		    = "Could not find the vm _*$($a)*_, are you sure that's correct?";
				"mrkdwn"	    = $true
			}
			Write-Output "Could not find the vm _*$($a)*_, are you sure that's correct?"
			Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
		}
	}
	
	if ([System.String]::IsNullOrEmpty($VMs) -eq $false)
	{
		# Filter Allowed to automate and user VMs
		$FilteredOutput = @()
		foreach ($b in $VMs)
		{
			$AutomateTags = $b.Tags["int_automate"] | ConvertFrom-VMTagJSON
			if ($AutomateTags.int_allow_automate -eq 'false')
			{
				$JSON = @{
					"response_type" = "ephemeral";
					"username"	    = "Stop My VM";
					"text"		    = "VM _*$($b.name)*_ isn't allowed to be automated so won't be shutdown.";
					"mrkdwn"	    = $true
				}
				Write-Output "VM _*$($b.name)*_ isn't allowed to be automated so won't be shutdown."
				Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
				continue
			}
			if ($b.tags['int_vm_type'] -ne 'user')
			{
				$JSON = @{
					"response_type" = "ephemeral";
					"username"	    = "Stop My VM";
					"text"		    = "VM _*$($b.name)*_ isn't a 'user' VM, so won't be shutdown.";
					"mrkdwn"	    = $true
				}
				Write-Output "VM _*$($b.name)*_ isn't a 'user' VM, so won't be shutdown."
				Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
				continue
			}
			if ([System.String]::IsNullOrEmpty($b.tags['int_slack_userid']))
			{
				$JSON = @{
					"response_type" = "ephemeral";
					"username"	    = "Stop My VM";
					"text"		    = "VM _*$($b.name)*_ isn't registered to anyone, so won't be shutdown. If you own this VM please register it with /verifymyvm";
					"mrkdwn"	    = $true
				}
				Write-Output "VM _*$($b.name)*_ isn't registered to anyone, so won't be shutdown. If you own this VM please register it with /verifymyvm"
				Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
				continue
			}
			if ($b.tags['int_slack_userid'] -ne $webhookbody.user_id)
			{
				$JSON = @{
					"response_type" = "ephemeral";
					"username"	    = "Stop My VM";
					"text"		    = "VM _*$($b.name)*_ isn't registerd to you, so won't be shutdown.";
					"mrkdwn"	    = $true
				}
				Write-Output "VM _*$($b.name)*_ isn't registerd to you, so won't be shutdown."
				Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
				continue
			}
			$FilteredOutput += $b
		}
		$webhookbody.email = $($FilteredOutput[0].Tags["int_owner"])
	}
	else
	{
		$JSON = @{
			"response_type" = "ephemeral";
			"username"	    = "Stop My VM";
			"text"		    = "No VMs found with the name(s) passed, you entered _*$($webhookbody.text)*_.";
			"mrkdwn"	    = $true
		}
		Write-Output "No VMs found with the name(s) passed, you entered _*$($webhookbody.text)*_."
		Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
		break
	}
	
}

if ([system.String]::IsNullOrEmpty($FilteredOutput) -eq $false)
{
	foreach ($a in $FilteredOutput)
	{
		$VM = Get-AzureRMVM -Name $a.Name -ResourceGroupName $a.ResourceGroupName -Status

		if (($VM.Statuses | where code -Like "PowerState*").DisplayStatus -eq "VM Running")
		{
			try
			{
				Write-Output "Stopping $($VM.Name).."
				$null = Stop-AzureRMVM -Name $($VM.Name) -ResourceGroupName $($VM.ResourceGroupName) -Force
				Write-Output "VM $($VM.Name) stopped!"
				if (($email) -and ([System.String]::IsNullOrEmpty($webhookbody.response_url)))
				{
					Send-MailMessage @EmailSplat -Subject "[Success] Stoped $($VM.Name) Successfully!" -Body $Success
				}
				if ([System.String]::IsNullOrEmpty($webhookbody.response_url) -eq $false)
				{
					$JSON = @{
						"response_type" = "ephemeral";
						"username"	    = "Stop My VM";
						"text"		    = "Stopped VM _*$($a.Name)*_, go you!";
						"mrkdwn"	    = $true						
					}
					Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
				}
			}
			Catch
			{
				$Fail = $Fail.Replace('{1}', $($_.Exception.Message))
				Write-Output "Failed to stop VM $($VM.Name)"

				if (($email) -and ([System.String]::IsNullOrEmpty($webhookbody.response_url)))
				{
					Send-MailMessage @EmailSplat -Subject "[Failure] Failed to stop $($VM.Name)" -Body $Fail
				}
				if ([System.String]::IsNullOrEmpty($webhookbody.response_url) -eq $false)
				{
					$JSON = @{
						"response_type" = "ephemeral";
						"username"	    = "Stop My VM";
						"text"		    = "Failed to stop VM _*$($a.Name)*_.. Exception: $($_.Exception.Message)";
						"mrkdwn"	    = $true
					}
					Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
				}
			}
		}
		else
		{
			Write-Output "Failed to stop VM, its current state is $(($VM.Statuses | where code -Like "PowerState*").DisplayStatus)"

			if (($email) -and ([System.String]::IsNullOrEmpty($webhookbody.response_url)))
			{
				Send-MailMessage @EmailSplat -Subject "[Warning] Failed to Stop $($VM.Name)" -Body $Fail
			}
			if ([System.String]::IsNullOrEmpty($webhookbody.response_url) -eq $false)
			{
				$JSON = @{
					"response_type" = "ephemeral";					
					"username"	    = "Stop My VM";
					"text"		    = "Failed to stop VM _*$($a.Name)*_ it's currently in state _$(($VM.Statuses | where code -Like "PowerState*").DisplayStatus)_.";
					"mrkdwn"	    = $true
				}
				Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			}
		}
	}
}
else
{
	if ([System.String]::IsNullOrEmpty($webhookbody.response_url) -eq $false)
	{
		$JSON = @{
			"response_type" = "ephemeral";
			"username"	    = "Stop My VM";
			"text"		    = "Looks like there aren't any VMs we can work with, so naturally we had nothing to stop!";
			"mrkdwn"	    = $true
		}
		Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
	}
	Write-Output "Looks like there aren't any VMs we can work with, breaking."
	break
}