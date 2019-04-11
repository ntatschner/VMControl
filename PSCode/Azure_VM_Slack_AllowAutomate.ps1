# Disable Automation via Tag from Slack

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


# Build out body input to user object object
$webhookbody = New-Object System.Management.Automation.PSObject
$propNames = ($(ConvertFrom-Json $WebhookData.RequestBody).RequestBody | Select-String -Pattern '(\w*)(\=)' -AllMatches).Matches | % { $_.Groups[1].value }
foreach ($a in $propNames)
{
	$webhookbody | Add-Member -MemberType NoteProperty -Name $a -Value ($(ConvertFrom-Json $WebhookData.RequestBody).RequestBody | Select-String -Pattern "($($a)=)([a-zA-Z0-9\.%$@]*)").Matches.Groups[2].Value
}
$webhookbody | Add-Member -MemberType NoteProperty -Name SubscriptionID -Value $(ConvertFrom-Json $WebhookData.RequestBody).SubscriptionID
$webhookbody | Add-Member -MemberType NoteProperty -Name email -Value ""
$webhookbody.response_url = $webhookbody.response_url.replace('%2F', '/').Replace('%3A', ':')
Write-Output $webhookbody

if ($WebhookData -ne $null)
{
	# Azure Connection
	# Getting Connection Credentials
	$connection = Get-AutomationConnection -Name AzureRunAsConnection
	
	$null = Connect-AzureRmAccount -ServicePrincipal -Tenant $connection.TenantID `
								   -ApplicationID $connection.ApplicationID -CertificateThumbprint $connection.CertificateThumbprint
	
	# Setting context to Internal Services for User VMs
	$null = Set-AzureRmContext -SubscriptionId $webhookbody.SubscriptionID
	
}

# Find all VMs owned by user
if ([System.String]::isNullorEmpty($webhookbody.user_id) -eq $false)
{
	$VMs = Get-AzureRmResource -TagName "int_slack_userid" -TagValue $webhookbody.user_id -ResourceType Microsoft.Compute/virtualMachines
}
if ([System.String]::IsNullOrEmpty($VMs)) {
	$JSON = @{
		"response_type" = "ephemeral";
		"username"	    = "Start My VM";
		"text"		    = "Your Slack user isn't registered with any VMs, have you run /VerifyMyVM yet?";
		"mrkdwn"	    = $true
	}
	Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
	break
}
# Filter Allowed to automate and user VMs
$FilteredOutput = @()
foreach ($b in $VMs)
{
	if ($b.tags['int_vm_type'] -eq 'user')
	{
		$FilteredOutput += $b
	}
}
$webhookbody.email = $($FilteredOutput[0].Tags["int_owner"])

if (([System.String]::IsNullOrEmpty($webhookbody.Text) -eq $false) -and ($webhookbody.Text -in "enable","disable"))
{
	foreach ($a in $FilteredOutput)
	{
		$AutomateTags = $a.Tags["int_automate"] | ConvertFrom-VMTagJSON
		if ($webhookbody.Text -eq "disable")
		{
			if ($AutomateTags.int_allow_automate -eq "true")
			{
				$AutomateTags.int_allow_automate = "false"
				$a.Tags["int_automate"] = $($AutomateTags | ConvertTo-VMTagJSON)
				$null = Set-AzureRMResource -Name $a.Name -ResourceType "Microsoft.Compute/virtualMachines" -ResourceGroupName $a.ResourceGroupName -Tag $a.Tags -Force -confirm:$false
				Write-Output "$($a.Name) is now set to int_allow_automate: false"
				$JSON = @{
					"response_type" = "ephemeral";
					"text"		    = "Your VM $($a.Name) is now no longer set to allow automation"
				}
				Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			}
			else
			{
				Write-Output "$($a.Name) is already set to int_allow_automate: false"
				$JSON = @{
					"response_type" = "ephemeral";
					"text"		    = "Your VM $($a.Name) is already set to not allow automation"
				}
				Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			}
		}
		elseif ($webhookbody.Text -eq "enable")
		{
			if ($AutomateTags.int_allow_automate -eq "false")
			{
				$AutomateTags.int_allow_automate = "true"
				$a.Tags["int_automate"] = $($AutomateTags | ConvertTo-VMTagJSON)
				$null = Set-AzureRMResource -Name $a.Name -ResourceType "Microsoft.Compute/virtualMachines" -ResourceGroupName $a.ResourceGroupName -Tag $a.Tags -Force -confirm:$false
				Write-Output "$($a.Name) is now set to int_allow_automate: true"
				$JSON = @{
					"response_type" = "ephemeral";
					"text"		    = "Your VM $($a.Name) is now set to allow automation"
				}
				Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			}
			else
			{
				Write-Output "$($a.Name) is already set to int_allow_automate: true"
				$JSON = @{
					"response_type" = "ephemeral";
					"text"		    = "Your VM $($a.Name) is already set to allow automation"
				}
				Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			}
		}
		
	}
}
else
{
	Write-Output "Invalid or No input supplied by command"
	$JSON = @{
		"response_type" = "ephemeral";
		"text"		    = "Invalid or no input supplied by command, please enter enable or disable to modify the automations settings."
	}
	Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
}	