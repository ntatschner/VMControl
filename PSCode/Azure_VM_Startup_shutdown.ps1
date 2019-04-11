# User VM Start up and Shutdown

# Vars

$SubscriptionID = 'ffd616d2-3b41-480e-8619-6974241d43ac'
$weekend = (get-date).DayOfWeek -like "s*"

# Azure Connection
# Connect to AzureRM
$connection = Get-AutomationConnection -Name AzureRunAsConnection
$null = Connect-AzureRmAccount -ServicePrincipal -Tenant $connection.TenantID `
							   -ApplicationID $connection.ApplicationID -CertificateThumbprint $connection.CertificateThumbprint | Tee-Object -Variable 'ConnectionObj'
# Set the subscription context
if ([System.String]::isNullorEmpty($SubscriptionID) -eq $false)
{
	$null = Set-AzureRmContext -Subscription $SubscriptionID
}
else
{
	Write-Output "Subscription ID empty, breaking"
	break
}

#region Functions

function StartUpTime
{
	param
	(
		[parameter(Mandatory = $true)]
		[object]$tag
	)
	
	if ([System.String]::IsNullOrEmpty($tag.int_auto_schedule_slot) -eq $false)
	{
		return [string]$tag.int_auto_schedule_slot.Split('-')[0]
	}
	else
	{
		return [string]"08:00"
	}
}

function ShutdownTime
{
	param
	(
		[parameter(Mandatory = $true)]
		[object]$tag
	)
	
	if ([System.String]::IsNullOrEmpty($tag) -eq $false)
	{
		# Returns Tag Value
		return [string]$tag.int_auto_schedule_slot.Split('-')[1]
	}
	else
	{
		# Returns default if not tag value was specified
		return [string]"18:00"
	}
}

# Tag JSON Functions

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

#endregion Functions

#region Finding VMs
# Finding VMs
Write-Output "Getting User VMs if they are allowed to be automated."
$UserVMs = Get-AzureRmResource -TagName 'int_vm_type' -TagValue 'user' -ResourceType Microsoft.Compute/virtualMachines
Write-Output "Extending VM Object with status infomation"
$VMAllowedAutomate = @()
foreach ($a in $UserVMs)
{
	$VM = Get-AzureRMVM -Name $a.Name -ResourceGroupName $a.ResourceGroupName
	if ([System.String]::IsNullOrEmpty($VM.Tags["int_automate"]))
	{
		# Adding default values
		Write-Output "int_automate not found on user VM $($VM.Name), Adding default values now."
		$VM.Tags.Add("int_automate", '{"int_auto_weekday":"schedule","int_allow_automate":"true","int_auto_schedule_slot":"08:00-18:00","int_auto_weekend":"off","int_automate_postpone":"false"}')
		Update-AzureRMVM -VM $VM -ResourceGroupName $VM.ResourceGroupName -Tag $VM.Tags | Out-Null
	}
	$AutomateTags = $VM.Tags["int_automate"] | ConvertFrom-VMTagJSON
	if ($AutomateTags.int_allow_automate -eq 'true')
	{
		# Adding extra info to vm object
		$VM | Add-Member -MemberType NoteProperty -Name "State" -Value $((Get-AzureRMVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Status).Statuses | Where-Object code -Like "PowerState*").DisplayStatus
		$VMAllowedAutomate += $VM
	}
}
#endregion Finding VMS

Write-Output "Starting main loop"
foreach ($VM in $VMAllowedAutomate)
{
	Write-Output "Processing VM $($VM.Name).."
	$AutomateTags = $VM.Tags["int_automate"] | ConvertFrom-VMTagJSON
	$ScheduleType = ""
	if ($weekend)
	{
		$ScheduleType = $AutomateTags.int_auto_weekend
	}
	else
	{
		$ScheduleType = $AutomateTags.int_auto_weekday
	}
	$Schedule = Get-AzureRMAutomationSchedule -Name "Every_Hour" -ResourceGroupName "INT_Domain-rg" -AutomationAccountName "svc-vm-state"
	$ScheduleDateTime = $Schedule.NextRun.DateTime.AddHours(-1)
	
	Write-Output "VM $($VM.Name) ScheduleType is: $($ScheduleType)"
	#region Shutdown
	# Shutdown flow - Start
	if ($VM.state -notin "vm stopped", "vm stopping", "vm deallocating", "vm deallocated")
	{
		$VMScheduledRunDateTime = Get-Date -Date "$((Get-Date).ToShortDateString()) $(ShutdownTime -tag $AutomateTags)"
		$CurrentShutdownInterval = $ScheduleDateTime -eq $VMScheduledRunDateTime
		
		# Notify User of impending shutdown
		$NextShutdownInterval = $Schedule.NextRun.DateTime -eq $VMScheduledRunDateTime
		$JobProperties = $VM, $CurrentShutdownInterval, $NextShutdownInterval, $Schedule, $AutomateTags, $ScheduleType
		
		# Create Jobs and output logic
		$Job = {
			param
			(
				$VM,
				[bool]$CurrentShutdownInterval,
				[bool]$NextShutdownInterval,
				$CurrentRunDateTime,
				$AutomateTags,
				$ScheduleType
			)
			
			#region Functions
			
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
			
			#endregion functions
			
			if ($ScheduleType -eq "Schedule")
			{
				if (($AutomateTags.int_automate_postpone -eq "true") -and ($CurrentShutdownInterval -eq $true))
				{
					# VM postpone step
					Write-Output "Skipping VM $($VM.Name) as it's been set to postpone shutdown this time."
					$AutomateTags.int_automate_postpone = "false"
					$VM.Tags["int_automate"] = $($AutomateTags | ConvertTo-VMTagJSON)
					$null = Set-AzureRMResource -ResourceName $VM.Name -ResourceType "Microsoft.Compute/virtualMachines" -ResourceGroupName $VM.ResourceGroupName -Tags $VM.Tags -Force -confirm:$false
					Write-Output "Postpone value set back to false for VM $($VM.Name)"
				}
				else
				{
					if (($CurrentShutdownInterval -eq $false) -and ($NextShutdownInterval -eq $false))
					{
						Write-Output "VM $($VM.Name) not scheduled to shutdown at this time."
					}
					elseif (($CurrentShutdownInterval -eq $false) -and ($NextShutdownInterval -eq $true))
					{
						# VM postpone email notify step
						Write-Output "VM $($VM.Name) is scheduled to shutdown at $($CurrentRunDateTime.NextRun), alerting user and offering postponement"
						$JSON = @{
							"EmailAddress" = $VM.Tags["int_Owner"];
							"VMName"	   = $VM.Name;
							"ResourceGroupName" = $VM.ResourceGroupName;
							"CurrentState" = $($(Get-AzureRMVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Status).Statuses | Where-Object code -Like "PowerState*").DisplayStatus;
							"ShutdownTime" = $CurrentRunDateTime.NextRun
						}
						
						$EmailTrigger = Invoke-WebRequest -Uri "https://prod-122.westeurope.logic.azure.com:443/workflows/70b8df8211864517b69ba793a39e9e24/triggers/manual/paths/invoke?api-version=2016-06-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=VuWiA85m26KW5IttoJC0kTwJ7P4xk5tTGQBt_acnu34" `
														  -Method Post -ContentType "application/json" -Body (ConvertTo-Json -InputObject $JSON) -UseBasicParsing
						Write-Output "$((ConvertFrom-Json $EmailTrigger).Response)"
					}
					elseif ($CurrentShutdownInterval)
					{
						# VM Shutdown Step
						Write-Output "Stopping VM $($VM.Name)"
						try
						{
							# Place Holder for Maintanance Mode scheduling
							# MM Start
							try
							{
								$Headers = @{
									'datetime' = $(Get-Date -Format "ddMMyy");
									'mode'	   = "on"
								}
								
								Invoke-WebRequest -Uri "http://$($VM.Name):7777" -Headers $Headers -Method Post -UseBasicParsing
							}
							catch
							{
								Write-Output "Failed to set maintainance mode."
							}
							
							# MM End
							
							Stop-AzureRMVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Force -Confirm:$false
						}
						catch
						{
							Write-Output "Failed to shutdown vm $($VM.name), Error: $($_.Exception.Message)"
						}
						
					}
				}
			}
			elseif ($ScheduleType -eq "off")
			{
				# VM Shutdown Step
				Write-Output "Stopping VM $($VM.Name)"
				try
				{
					# Place Holder for Maintanance Mode scheduling
					# MM Start
					try
					{
						$Headers = @{
							'datetime' = $(Get-Date -Format "ddMMyy");
							'mode'	   = "on"
						}
						
						Invoke-WebRequest -Uri "http://$($VM.Name):7777" -Headers $Headers -Method Post -UseBasicParsing
					}
					catch
					{
						Write-Output "Failed to set maintainance mode."
					}
					
					# MM End	
					
					Stop-AzureRMVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Force -Confirm:$false
					Write-Output "VM $($VM.Name) has been stopped."
				}
				catch
				{
					Write-Output "Failed to shutdown vm $($VM.name), Error: $($_.Exception.Message)"
				}
			}
			elseif ($ScheduleType -eq "on")
			{
				Write-Output "VM $($VM.Name) is set to stay on at this time."
			}
		} # End Job Logic
		Start-Job -ScriptBlock $Job -ArgumentList $JobProperties -Name $("Shutdown-" + $VM.Name) | Out-Null
		Write-Output "Shutdown Job for VM $($VM.Name) Started"
	}
	Else
	{
		Write-Output "VM $($VM.Name) shutdown not needed"
	}
	#endregion Shutdown
	#region Startup
	
	# Startup 
	if ($VM.state -notin "vm running", "vm starting")
	{
		$VMScheduledRunDateTime = Get-Date -Date "$((Get-Date).ToShortDateString()) $(StartUpTime -tag $AutomateTags)"
		$CurrentStartupInterval = $ScheduleDateTime -eq $VMScheduledRunDateTime
		
		$StartJobProperties = $VM, $CurrentStartupInterval, $AutomateTags, $ScheduleType
		
		# Create Jobs and output logic
		$StartJob = {
			param
			(
				$VM,
				[bool]$CurrentStartupInterval,
				$AutomateTags,
				$ScheduleType
			)
			if ($ScheduleType -eq "Schedule")
			{
				if ($CurrentStartupInterval -eq $false)
				{
					Write-Output "VM $($VM.Name) not scheduled to startup at this time."
				}
				else
				{
					# VM startup Step
					Write-Output "starting VM $($VM.Name)"
					try
					{
						# Place Holder for Maintanance Mode scheduling
						# MM Start
						try
						{
							$Headers = @{
								'datetime' = $(Get-Date -Format "ddMMyy");
								'mode'	   = "off"
							}
							
							Invoke-WebRequest -Uri "http://$($VM.Name):7777" -Headers $Headers -Method Post -UseBasicParsing
						}
						catch
						{
							Write-Output "Failed to set maintainance mode."
						}
						
						# MM End
						
						Write-Output "Starting VM $($VM.Name)"
						Start-AzureRMVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Confirm:$false
						Write-Output "VM $($VM.Name) has been started"
					}
					catch
					{
						Write-Output "Faied to start vm $($VM.Name), Error: $($_.Exception.Message)"
					}
				}
			}
			elseif ($ScheduleType -eq "on")
			{
				# VM startup Step
				Write-Output "starting VM $($VM.Name)"
				try
				{
					# Place Holder for Maintanance Mode scheduling
					# MM Start
					try
					{
						$Headers = @{
							'datetime' = $(Get-Date -Format "ddMMyy");
							'mode'	   = "on"
						}
						
						Invoke-WebRequest -Uri "http://$($VM.Name):7777" -Headers $Headers -Method Post -UseBasicParsing
					}
					catch
					{
						Write-Output "Failed to set maintainance mode."
					}
					
					# MM End
					
					Start-AzureRMVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Confirm:$false
					Write-Output "VM $($VM.Name) has been started"
				}
				catch
				{
					Write-Output "Failed to startup vm $($VM.name), Error: $($_.Exception.Message)"
				}
			}
			elseif ($ScheduleType -eq "off")
			{
				Write-Output "VM $($VM.Name) set to off at this time."
			}
		} # End Job Logic
		Start-Job -ScriptBlock $StartJob -ArgumentList $StartJobProperties -Name $("Startup-" + $VM.Name) | Out-Null
		Write-Output "Start Job for VM $($VM.Name) Started"
	}
	Else
	{
		Write-Output "VM $($VM.Name) startup not needed"
	}
	
	#endregion Startup
}
Write-Output "###########.............starting job retreval..............################"
$LoopCount = 0
$dateNow = Get-Date
do
{
	$LoopCount++
	Get-Job | where state -in "Completed", "failed" | ForEach-Object -Process {
		Receive-Job -Job $_
		Remove-Job -Job $_
	}
	Write-Output "Waiting for jobs to finish.. | Running for $($ts = $(New-TimeSpan -Start $dateNow -End $(Get-Date)) ; if ($ts.TotalSeconds -lt 60) { "{0:n0}" -f $ts.TotalSeconds + " Second(s)"} elseif ($ts.Totalminutes -lt 60) { "{0:n0}" -f $ts.TotalMinutes + " Minute(s) and " + ("{0:n0}" -f $ts.Seconds) + " seconds"} else { "{0:n0}" -f $ts.TotalHours + " Hour(s)"} )"
	Start-Sleep -Seconds 5
}
while (([System.String]::IsNullOrEmpty($(Get-Job)) -eq $false) -and ($LoopCount -le 3000))
Write-Output "########################............Completed...........###########################"