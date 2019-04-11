# Azure VM Start up and Shutdown script
# Vars

$vmProps = @{
	
}

# Getting Connection Credentials
$connection = Get-AutomationConnection -Name AzureRunAsConnection

#Connecting to AzureRM
$null = Connect-AzureRmAccount -ServicePrincipal -Tenant $connection.TenantID `
							   -ApplicationID $connection.ApplicationID -CertificateThumbprint $connection.CertificateThumbprint
# Connecting to SharePoint Online

$Site = Connect-PnPOnline -Url "https://squaredup.sharepoint.com/sites/Systems"

# Setting context to Internal Services for User VMs
$null = Set-AzureRmContext -SubscriptionId $(Get-AutomationVariable -Name 'SubscriptionID')
# Getting all VMs with Tag "int_vm_type: user"
$userVMs = Get-AzureRmResource -ResourceType Microsoft.Compute/virtualMachines -TagName "int_vm_type" -TagValue "user"
# Starting main loop
foreach ($a in $userVMs)
{
	$VMObj = Get-AzureRMVM -Name $a.Name -ResourceGroupName $a.ResourceGroupName -Status
	$VMObj | Add-Member -TypeName NoteProperty -Name 'PowerState' -Value ($_.statuses | where code -Like "powerstate/*").code.split('/')[1]
}