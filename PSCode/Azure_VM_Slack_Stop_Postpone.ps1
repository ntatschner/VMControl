# VM Shutdown Postpont Tag Modify

# Input Parameters
param
(
	[object]$Webhookdata
)
# Vars 

$SubscriptionID = Get-AutomationVariable -Name 'SubscriptionID'

# Tag JSON Functions
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
				else { $true } })]
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

#endregion Functions

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
	
	$VM = Get-AzureRMVM -ResourceName $WebhookObj.VMName -ResourceGroupName $WebhookObj.ResourceGroupName
	$AutomateTags = $VM.Tags["int_automate"] | ConvertFrom-VMTagJSON
	
	if ([System.String]::IsNullOrEmpty($VM.Tags["int_automate"]))
	{
		# Adding default values
		Write-Output "Adding default values"
		$VM.Tags.Add("int_automate", '{"int_auto_weekday":"schedule","int_allow_automate":"true","int_auto_schedule_slot":"08:00-18:00","int_auto_weekend":"off","int_automate_postpone":"false"}')
		Update-AzureRMVM -VM $VM -ResourceGroupName $VM.ResourceGroupName -Tag $VM.Tags | Out-Null
	}
	else
	{
		Write-Output "Modifying postpone value to true"
		$AutomateTags.int_automate_postpone = "true"
		$VM.Tags["int_automate"] = $AutomateTags | ConvertTo-VMTagJSON
		$null = Set-AzureRMResource -ResourceName $VM.Name -ResourceType "Microsoft.Compute/virtualMachines" -ResourceGroupName $VM.ResourceGroupName -Tag $VM.Tags -Force -confirm:$false
	}
}