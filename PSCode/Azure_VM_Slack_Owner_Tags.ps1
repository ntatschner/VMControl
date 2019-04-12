# Slack VM Owner Verification - Azure Tags

# Input Parameters
param
(
	[object]$Webhookdata
)
# Vars 

$SubscriptionID = Get-AutomationVariable -Name 'SubscriptionID'
# Email Setup

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

$Cred = Get-AutomationPSCredential -Name "Alerts Email Account"
$email = $true
if ([System.String]::IsNullOrEmpty($Cred))
{
	Write-Output "Unable to send email alerts, credentials are missing."
	$email = $false
}

if ($WebhookData -ne $null)
{
	# Azure Connection
	# Getting Connection Credentials
	$connection = Get-AutomationConnection -Name AzureRunAsConnection
	
	$null = Connect-AzureRmAccount -ServicePrincipal -Tenant $connection.TenantID `
								   -ApplicationID $connection.ApplicationID -CertificateThumbprint $connection.CertificateThumbprint
	
	# Setting context to Internal Services for User VMs
	$null = Set-AzureRmContext -SubscriptionId $SubscriptionID
	
	$WebhookObj = ConvertFrom-Json -InputObject $Webhookdata.RequestBody
	
	# email props 
	$EmailSplat = @{
		'SMTPServer' = 'smtp.office365.com';
		'To'		 = $WebhookObj.email;
		'UseSSL'	 = $true;
		'Port'	     = "587";
		'From'	     = "Start My VM <smvm@Squaredup.com>";
		'BodyAsHtml' = $true;
		'Credential' = $Cred
	}
	
	$userVMs = Get-AzureRmResource -ResourceType Microsoft.Compute/virtualMachines -TagName "int_owner" -TagValue ($WebhookObj.email) | where -FilterScript { $_.Tags["int_owner"] -eq $WebhookObj.email }
	$userAlreadyOwned = @()
	$userRegisteredButNotOwned = @()
	$userAdded = @()
	$userAllowed = @()
	$userErrors = @()
	if ([System.String]::IsNullOrEmpty($userVMs) -eq $false)
	{
		foreach ($a in $userVMs)
		{
			$AutomateTags = $a.Tags["int_automate"] | ConvertFrom-VMTagJSON
			if ($a.tags['int_vm_type'] -eq 'user')
			{
					if ([System.String]::IsNullOrEmpty($a.Tags["int_slack_userid"]))
					{
						$a.Tags["int_slack_userid"] = $WebhookObj.user_id
						try
						{
							$null = Set-AzureRMResource -Name $a.Name -ResourceType "Microsoft.Compute/virtualMachines" -ResourceGroupName $a.ResourceGroupName -Tag $a.Tags -Force -confirm:$false
							Write-Output $("Added $($WebhookObj.user_id) as the owner of " + $a.Name)
							$userAdded += $a
						}
						Catch
						{
							Write-Output $("failed to add the owner to " + $a.Name + ", Error: $($_.Exception.Message)")
							$userErrors += "failed to add the owner to " + $a.Name + ", Error: $($_.Exception.Message)"
						}
					}
					elseif ($a.Tags["int_slack_userid"] -ne $WebhookObj.user_id)
					{
						Write-Output $($a.Name + "is already registered to Slack user $($a.Tags["int_slack_userid"])")
						$userRegisteredButNotOwned += $a
					}
					else
					{
						Write-Output $($a.Name + " is already owned by user $($WebhookObj.user_id)")
						$userAlreadyOwned += $a
					}
			}
		}
		# Email results
		$emailBuilder = "Hey $($WebhookObj.email),`nThe results of the /verifymyvm and your email responce are below;`n`n"
		
		if ([System.String]::isNullorEmpty($userAdded) -eq $false)
		{
			$emailBuilder += "Added slack user $($WebhookObj.user_id) as the owner of the following VMs`n$(if ($userAdded.count -gt 1) { $userAdded.Name -Join " ; " }
				else { $($userAdded.Name) })`n`n"
		}
		if ([System.String]::isNullorEmpty($userAlreadyOwned) -eq $false)
		{
			$emailBuilder += "User $($WebhookObj.user_id) is already the owner of the following VMs`n$(if ($userAlreadyOwned.count -gt 1) { $userAlreadyOwned.Name -Join " ; " }
				else { $($userAlreadyOwned.Name) })`n`n"
		}
		if ([System.String]::isNullorEmpty($userRegisteredButNotOwned) -eq $false)
		{
			# $emailBuilder += "Another user  is registered as the owner $($WebhookObj.user_id) as the owner of the following VMs`n$(if ($userAdded.count -gt 1) {$userAdded.Name -Join " ; "} else {$($userAdded.Name)})`n`n"
		}
		if ([System.String]::isNullorEmpty($userAllowed) -eq $false)
		{
			$emailBuilder += "Added slack user $($WebhookObj.user_id) as the owner of the following VMs`n$(if ($userAdded.count -gt 1) { $userAdded.Name -Join " ; " }
				else { $($userAdded.Name) })`n`n"
		}
		if ([System.String]::isNullorEmpty($userErrors) -eq $false)
		{
			$emailBuilder += "Added slack user $($WebhookObj.user_id) as the owner of the following VMs`n$(if ($userAdded.count -gt 1) { $userAdded.Name -Join " ; " }
				else { $($userAdded.Name) })`n`n"
		}
		Send-MailMessage @EmailSplat -Subject "[Info] Slack Verify My VM Command Output" -Body $emailBuilder
	}
	else
	{
		Send-MailMessage @EmailSplat -Subject "[Warning] No owned VMs found" -Body "Sorry, `nlooks like $($WebhookObj.email) isn't registered as an owner of any user VMs. `nSquaredup Systems Team"
		Write-Output "user isn't the owner of VMs"
	}
}
else
{
	Write-Output "Webhook data empty, breaking"
	break
}