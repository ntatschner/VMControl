param
(
	[object]$Webhookdata
)
Write-Output $webhookdata
if ($WebhookData -ne $null)
{
	
	# Build out body input to user object object
	$webhookbody = New-Object System.Management.Automation.PSObject
	$propNames = ($WebhookData.RequestBody | Select-String -Pattern '(\w*)(\=)' -AllMatches).Matches | % { $_.Groups[1].value }
	foreach ($a in $propNames)
	{
		$webhookbody | Add-Member -MemberType NoteProperty -Name $a -Value ($WebhookData.RequestBody | Select-String -Pattern "($($a)=)([a-zA-Z0-9\.%$@]*)").Matches.Groups[2].Value
	}

	$webhookbody | Add-Member -MemberType NoteProperty -Name email -Value ""
	$webhookbody.response_url = $webhookbody.response_url.replace('%2F', '/').Replace('%3A', ':')
	
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

# Functions

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

# Find all VMs owned by user
if ([System.String]::isNullorEmpty($webhookbody.user_id) -eq $false)
{
	$VMs = Get-AzureRmResource -TagName "int_slack_userid" -TagValue $webhookbody.user_id -ResourceType Microsoft.Compute/virtualMachines
}
if ([System.String]::IsNullOrEmpty($VMs))
{
	$JSON = @{
		"response_type" = "ephemeral";
		"username"	    = "Start My VM";
		"text"		    = "Your Slack user isn't registered with any VMs, have you run /VerifyMyVM yet?";
		"mrkdwn"	    = $true
	}
	Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
	break
}
# Filter User VMs
$ReturnMessage = @"
Here is the list of the user VMs you're set as the owner of.`n
"@
$count = 0
foreach ($b in $VMs)
{
	$AutomateTags = $b.Tags["int_automate"] | ConvertFrom-VMTagJSON
	if ($b.tags['int_vm_type'] -eq 'user')
	{
		$count++
		$vm = Get-AzureRMVM -Name $b.Name -ResourceGroupName $b.ResourceGroupName -Status
		$ReturnMessage += $($count.ToString() + ") " + $vm.Name + " |  Allowed Automate Set to: " + $($AutomateTags.int_allowed_automate) + " | Current State: " + $(($vm.Statuses | where code -Like "PowerState*").DisplayStatus) + "`n")
	}
}
if ($count -gt 0)
{
	$JSON = @{
		"response_type" = "ephemeral";
		"text"		    = "$ReturnMessage"
	}
	Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
}
else
{
	$JSON = @{
		"response_type" = "ephemeral";
		"text"		    = "Looks like you're not the owner of any VMs.. :("
	}
	Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
}
	