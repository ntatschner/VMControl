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
		Write-Output $webhookbody
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

# Gifs

$SuccessGifs = "https://media.giphy.com/media/nXxOjZrbnbRxS/giphy.gif", "https://media.giphy.com/media/3rUbeDiLFMtAOIBErf/giphy.gif", "https://media.giphy.com/media/111ebonMs90YLu/giphy.gif", "https://media.giphy.com/media/cbb8zL5wbNnfq/giphy.gif"
$WarningGifs = "https://media.giphy.com/media/3oz8xOvhnSpVOs9xza/giphy.gif", "https://media.giphy.com/media/pMaPGoGE6LvS8/giphy.gif", "https://media.giphy.com/media/iXPMNiu0DVIxG/giphy.gif", "https://media.giphy.com/media/14aUO0Mf7dWDXW/giphy.gif"
$FailedGifs = "https://media.giphy.com/media/sS8YbjrTzu4KI/giphy.gif", "https://media.giphy.com/media/w3Er0gW94cG8E/giphy.gif", "https://media.giphy.com/media/25quInpfBuSRi/giphy.gif", "https://media.giphy.com/media/HNEmXQz7A0lDq/giphy.gif", "https://media.giphy.com/media/p3lSp6MfxW4U0/giphy.gif"

# Vars and setup

# Get email credentials from store

$Cred = Get-AutomationPSCredential -Name "Alerts Email Account"
$email = $true
if ([System.String]::IsNullOrEmpty($Cred))
{
	Write-Output "Unable to send email alerts, credentials are missing."
	$email = $false
}

# Email Failure

$HtmlFail = @"
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">

<head>
    <title></title>
    <!--[if !mso]><!-- -->
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <!--<![endif]-->
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style type="text/css">
        #outlook a {
            padding: 0;
        }

        .ReadMsgBody {
            width: 100%;
        }

        .ExternalClass {
            width: 100%;
        }

        .ExternalClass * {
            line-height: 100%;
        }

        body {
            margin: 0;
            padding: 0;
            -webkit-text-size-adjust: 100%;
            -ms-text-size-adjust: 100%;
        }

        table,
        td {
            border-collapse: collapse;
            mso-table-lspace: 0pt;
            mso-table-rspace: 0pt;
        }

        img {
            border: 0;
            height: auto;
            line-height: 100%;
            outline: none;
            text-decoration: none;
            -ms-interpolation-mode: bicubic;
        }

        p {
            display: block;
            margin: 13px 0;
        }
    </style>
    <!--[if !mso]><!-->
    <style type="text/css">
        @media only screen and (max-width:480px) {
            @-ms-viewport {
                width: 320px;
            }

            @viewport {
                width: 320px;
            }
        }
    </style>
    <!--<![endif]-->
    <!--[if mso]><xml>  <o:OfficeDocumentSettings>    <o:AllowPNG/>    <o:PixelsPerInch>96</o:PixelsPerInch>  </o:OfficeDocumentSettings></xml><![endif]-->
    <!--[if lte mso 11]><style type="text/css">  .outlook-group-fix {    width:100% !important;  }</style><![endif]-->
    <!--[if !mso]><!-->
    <link href="https://fonts.googleapis.com/css?family=Cabin" rel="stylesheet" type="text/css">
    <style type="text/css">
        @import url(https://fonts.googleapis.com/css?family=Cabin);
    </style>
    <!--<![endif]-->
    <style type="text/css">
        @media only screen and (min-width:480px) {
            .mj-column-per-100 {
                width: 100% !important;
            }
        }
    </style>
</head>

<body style="background: #FFFFFF;">
    <div class="mj-container" style="background-color:#FFFFFF;">
        <!--[if mso | IE]>      <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="600" align="center" style="width:600px;">        <tr>          <td style="line-height:0px;font-size:0px;mso-line-height-rule:exactly;">      <![endif]-->
        <div style="margin:0px auto;max-width:600px;">
            <table role="presentation" cellpadding="0" cellspacing="0" style="font-size:0px;width:100%;" align="center"
                border="0">
                <tbody>
                    <tr>
                        <td style="text-align:center;vertical-align:top;direction:ltr;font-size:0px;padding:9px 0px 9px 0px;">
                            <!--[if mso | IE]>      <table role="presentation" border="0" cellpadding="0" cellspacing="0">        <tr>          <td style="vertical-align:top;width:600px;">      <![endif]-->
                            <div class="mj-column-per-100 outlook-group-fix" style="vertical-align:top;display:inline-block;direction:ltr;font-size:13px;text-align:left;width:100%;">
                                <table role="presentation" cellpadding="0" cellspacing="0" style="vertical-align:top;"
                                    width="100%" border="0">
                                    <tbody>
                                        <tr>
                                            <td style="word-wrap:break-word;font-size:0px;padding:22px 22px 22px 22px;"
                                                align="center">
                                                <div style="cursor:auto;color:#D0021B;font-family:Cabin, sans-serif;font-size:11px;line-height:1.5;text-align:center;">
                                                    <p><strong><span style="font-size:26px;">Oh No! Looks like we
                                                                failed to start {0}</span></strong></p>
                                                </div>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td style="word-wrap:break-word;font-size:0px;padding:0px 0px 0px 0px;"
                                                align="center">
                                                <table role="presentation" cellpadding="0" cellspacing="0" style="border-collapse:collapse;border-spacing:0px;"
                                                    align="center" border="0">
                                                    <tbody>
                                                        <tr>
                                                            <td style="width:336px;"><img alt="" title="" height="auto"
                                                                    src="{2}"
                                                                    style="border:none;border-radius:0px;display:block;font-size:13px;outline:none;text-decoration:none;width:100%;height:auto;"
                                                                    width="336"></td>
                                                        </tr>
                                                    </tbody>
                                                </table>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td style="word-wrap:break-word;font-size:0px;padding:15px 15px 15px 15px;"
                                                align="center">
                                                <div style="cursor:auto;color:#000000;font-family:Merriweather, Georgia, serif;font-size:11px;line-height:1.5;text-align:center;">
                                                    <p>Here is is tecnical info for nerds;</p>
                                                    <p>{1}</p>
                                                </div>
                                            </td>
                                        </tr>
                                    </tbody>
                                </table>
                            </div>
                            <!--[if mso | IE]>      </td></tr></table>      <![endif]-->
                        </td>
                    </tr>
                </tbody>
            </table>
        </div>
        <!--[if mso | IE]>      </td></tr></table>      <![endif]-->
    </div>
</body>

</html>
"@

$HtmlSuccess = @"
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">

<head>
    <title></title>
    <!--[if !mso]><!-- -->
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <!--<![endif]-->
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style type="text/css">
        #outlook a {
            padding: 0;
        }

        .ReadMsgBody {
            width: 100%;
        }

        .ExternalClass {
            width: 100%;
        }

        .ExternalClass * {
            line-height: 100%;
        }

        body {
            margin: 0;
            padding: 0;
            -webkit-text-size-adjust: 100%;
            -ms-text-size-adjust: 100%;
        }

        table,
        td {
            border-collapse: collapse;
            mso-table-lspace: 0pt;
            mso-table-rspace: 0pt;
        }

        img {
            border: 0;
            height: auto;
            line-height: 100%;
            outline: none;
            text-decoration: none;
            -ms-interpolation-mode: bicubic;
        }

        p {
            display: block;
            margin: 13px 0;
        }
    </style>
    <!--[if !mso]><!-->
    <style type="text/css">
        @media only screen and (max-width:480px) {
            @-ms-viewport {
                width: 320px;
            }

            @viewport {
                width: 320px;
            }
        }
    </style>
    <!--<![endif]-->
    <!--[if mso]><xml>  <o:OfficeDocumentSettings>    <o:AllowPNG/>    <o:PixelsPerInch>96</o:PixelsPerInch>  </o:OfficeDocumentSettings></xml><![endif]-->
    <!--[if lte mso 11]><style type="text/css">  .outlook-group-fix {    width:100% !important;  }</style><![endif]-->
    <!--[if !mso]><!-->
    <link href="https://fonts.googleapis.com/css?family=Cabin" rel="stylesheet" type="text/css">
    <style type="text/css">
        @import url(https://fonts.googleapis.com/css?family=Cabin);
    </style>
    <!--<![endif]-->
    <style type="text/css">
        @media only screen and (min-width:480px) {
            .mj-column-per-100 {
                width: 100% !important;
            }
        }
    </style>
</head>

<body style="background: #FFFFFF;">
    <div class="mj-container" style="background-color:#FFFFFF;">
        <!--[if mso | IE]>      <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="600" align="center" style="width:600px;">        <tr>          <td style="line-height:0px;font-size:0px;mso-line-height-rule:exactly;">      <![endif]-->
        <div style="margin:0px auto;max-width:600px;">
            <table role="presentation" cellpadding="0" cellspacing="0" style="font-size:0px;width:100%;" align="center"
                border="0">
                <tbody>
                    <tr>
                        <td style="text-align:center;vertical-align:top;direction:ltr;font-size:0px;padding:9px 0px 9px 0px;">
                            <!--[if mso | IE]>      <table role="presentation" border="0" cellpadding="0" cellspacing="0">        <tr>          <td style="vertical-align:top;width:600px;">      <![endif]-->
                            <div class="mj-column-per-100 outlook-group-fix" style="vertical-align:top;display:inline-block;direction:ltr;font-size:13px;text-align:left;width:100%;">
                                <table role="presentation" cellpadding="0" cellspacing="0" style="vertical-align:top;"
                                    width="100%" border="0">
                                    <tbody>
                                        <tr>
                                            <td style="word-wrap:break-word;font-size:0px;padding:22px 22px 22px 22px;"
                                                align="center">
                                                <div style="cursor:auto;color:	#32CD32;font-family:Cabin, sans-serif;font-size:11px;line-height:1.5;text-align:center;">
                                                    <p><strong><span style="font-size:26px;">Wahoo! the VM {0} has started!</span></strong></p>
                                                </div>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td style="word-wrap:break-word;font-size:0px;padding:0px 0px 0px 0px;"
                                                align="center">
                                                <table role="presentation" cellpadding="0" cellspacing="0" style="border-collapse:collapse;border-spacing:0px;"
                                                    align="center" border="0">
                                                    <tbody>
                                                        <tr>
                                                            <td style="width:336px;"><img alt="" title="" height="auto"
                                                                    src="{2}"
                                                                    style="border:none;border-radius:0px;display:block;font-size:13px;outline:none;text-decoration:none;width:100%;height:auto;"
                                                                    width="336"></td>
                                                        </tr>
                                                    </tbody>
                                                </table>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td style="word-wrap:break-word;font-size:0px;padding:15px 15px 15px 15px;"
                                                align="center">
                                                <div style="cursor:auto;color:#000000;font-family:Merriweather, Georgia, serif;font-size:11px;line-height:1.5;text-align:center;">
                                                    <p>You're welcome! :P</p>
                                                </div>
                                            </td>
                                        </tr>
                                    </tbody>
                                </table>
                            </div>
                            <!--[if mso | IE]>      </td></tr></table>      <![endif]-->
                        </td>
                    </tr>
                </tbody>
            </table>
        </div>
        <!--[if mso | IE]>      </td></tr></table>      <![endif]-->
    </div>
</body>

</html>
"@

$HtmlWarning = @"
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">

<head>
    <title></title>
    <!--[if !mso]><!-- -->
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <!--<![endif]-->
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style type="text/css">
        #outlook a {
            padding: 0;
        }

        .ReadMsgBody {
            width: 100%;
        }

        .ExternalClass {
            width: 100%;
        }

        .ExternalClass * {
            line-height: 100%;
        }

        body {
            margin: 0;
            padding: 0;
            -webkit-text-size-adjust: 100%;
            -ms-text-size-adjust: 100%;
        }

        table,
        td {
            border-collapse: collapse;
            mso-table-lspace: 0pt;
            mso-table-rspace: 0pt;
        }

        img {
            border: 0;
            height: auto;
            line-height: 100%;
            outline: none;
            text-decoration: none;
            -ms-interpolation-mode: bicubic;
        }

        p {
            display: block;
            margin: 13px 0;
        }
    </style>
    <!--[if !mso]><!-->
    <style type="text/css">
        @media only screen and (max-width:480px) {
            @-ms-viewport {
                width: 320px;
            }

            @viewport {
                width: 320px;
            }
        }
    </style>
    <!--<![endif]-->
    <!--[if mso]><xml>  <o:OfficeDocumentSettings>    <o:AllowPNG/>    <o:PixelsPerInch>96</o:PixelsPerInch>  </o:OfficeDocumentSettings></xml><![endif]-->
    <!--[if lte mso 11]><style type="text/css">  .outlook-group-fix {    width:100% !important;  }</style><![endif]-->
    <!--[if !mso]><!-->
    <link href="https://fonts.googleapis.com/css?family=Cabin" rel="stylesheet" type="text/css">
    <style type="text/css">
        @import url(https://fonts.googleapis.com/css?family=Cabin);
    </style>
    <!--<![endif]-->
    <style type="text/css">
        @media only screen and (min-width:480px) {
            .mj-column-per-100 {
                width: 100% !important;
            }
        }
    </style>
</head>

<body style="background: #FFFFFF;">
    <div class="mj-container" style="background-color:#FFFFFF;">
        <!--[if mso | IE]>      <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="600" align="center" style="width:600px;">        <tr>          <td style="line-height:0px;font-size:0px;mso-line-height-rule:exactly;">      <![endif]-->
        <div style="margin:0px auto;max-width:600px;">
            <table role="presentation" cellpadding="0" cellspacing="0" style="font-size:0px;width:100%;" align="center"
                border="0">
                <tbody>
                    <tr>
                        <td style="text-align:center;vertical-align:top;direction:ltr;font-size:0px;padding:9px 0px 9px 0px;">
                            <!--[if mso | IE]>      <table role="presentation" border="0" cellpadding="0" cellspacing="0">        <tr>          <td style="vertical-align:top;width:600px;">      <![endif]-->
                            <div class="mj-column-per-100 outlook-group-fix" style="vertical-align:top;display:inline-block;direction:ltr;font-size:13px;text-align:left;width:100%;">
                                <table role="presentation" cellpadding="0" cellspacing="0" style="vertical-align:top;"
                                    width="100%" border="0">
                                    <tbody>
                                        <tr>
                                            <td style="word-wrap:break-word;font-size:0px;padding:22px 22px 22px 22px;"
                                                align="center">
                                                <div style="cursor:auto;color:	#E5E500;font-family:Cabin, sans-serif;font-size:11px;line-height:1.5;text-align:center;">
                                                    <p><strong><span style="font-size:26px;">Looks like you either don't have any VMs or none have been allowed to be automated, speak to systems if you beleive this is incorrect.</span></strong></p>
                                                </div>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td style="word-wrap:break-word;font-size:0px;padding:0px 0px 0px 0px;"
                                                align="center">
                                                <table role="presentation" cellpadding="0" cellspacing="0" style="border-collapse:collapse;border-spacing:0px;"
                                                    align="center" border="0">
                                                    <tbody>
                                                        <tr>
                                                            <td style="width:336px;"><img alt="" title="" height="auto"
                                                                    src="{2}"
                                                                    style="border:none;border-radius:0px;display:block;font-size:13px;outline:none;text-decoration:none;width:100%;height:auto;"
                                                                    width="336"></td>
                                                        </tr>
                                                    </tbody>
                                                </table>
                                            </td>
                                        </tr>
                                        <tr>
                                            <td style="word-wrap:break-word;font-size:0px;padding:15px 15px 15px 15px;"
                                                align="center">
                                                <div style="cursor:auto;color:#000000;font-family:Merriweather, Georgia, serif;font-size:11px;line-height:1.5;text-align:center;">
                                                    <p>"Technical Details";</p>
													<p>The VMs you're the owner of are either set to 'int_allowed_automate = false' or you're not set as an owner of any VMs, breaking.</p>
                                                </div>
                                            </td>
                                        </tr>
                                    </tbody>
                                </table>
                            </div>
                            <!--[if mso | IE]>      </td></tr></table>      <![endif]-->
                        </td>
                    </tr>
                </tbody>
            </table>
        </div>
        <!--[if mso | IE]>      </td></tr></table>      <![endif]-->
    </div>
</body>

</html>
"@

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

# Checking Webhook and modifying depending on source
if ([System.String]::IsNullOrEmpty($webhookbody.user_id) -eq $false)
{
	$VMs = @()
	# Find all VMs owned by user using SlackID if no input was supplied
	if (([System.String]::isNullorEmpty($webhookbody.user_id) -eq $false) -and ([System.String]::IsNullOrEmpty($webhookbody.text)))
	{
		$VMs = Get-AzureRmResource -TagName "int_slack_userid" -TagValue $webhookbody.user_id -ResourceType Microsoft.Compute/virtualMachines
	}
	else
	{
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
					"text"		    = "VM _*$($b.name)*_ isn't allowed to be automated so won't be started.";
					"mrkdwn"	    = $true
				}
				Write-Output "VM _*$($b.name)*_ isn't allowed to be automated so won't be started."
				Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
				continue
			}
			if ($b.tags['int_vm_type'] -ne 'user')
			{
				$JSON = @{
					"response_type" = "ephemeral";
					"username"	    = "Stop My VM";
					"text"		    = "VM _*$($b.name)*_ isn't a 'user' VM, so won't be started.";
					"mrkdwn"	    = $true
				}
				Write-Output "VM _*$($b.name)*_ isn't a 'user' VM, so won't be started."
				Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
				continue
			}
			if ([System.String]::IsNullOrEmpty($b.tags['int_slack_userid']))
			{
				$JSON = @{
					"response_type" = "ephemeral";
					"username"	    = "Stop My VM";
					"text"		    = "VM _*$($b.name)*_ isn't registered to anyone, so won't be started. If you own this VM please register it with /verifymyvm";
					"mrkdwn"	    = $true
				}
				Write-Output "VM _*$($b.name)*_ isn't registered to anyone, so won't be started. If you own this VM please register it with /verifymyvm"
				Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
				continue
			}
			if ($b.tags['int_slack_userid'] -ne $webhookbody.user_id)
			{
				$JSON = @{
					"response_type" = "ephemeral";
					"username"	    = "Stop My VM";
					"text"		    = "VM _*$($b.name)*_ isn't registerd to you, so won't be started.";
					"mrkdwn"	    = $true
				}
				Write-Output "VM _*$($b.name)*_ isn't registerd to you, so won't be started."
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
			"username"	    = "Start My VM";
			"text"		    = "Your Slack user isn't registered with any VMs, have you run /VerifyMyVM yet?";
			"mrkdwn"	    = $true
		}
		Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
		break
	}
	
}
else
{
	# Find all VMs owned by user using email address
	if ([System.String]::isNullorEmpty($webhookbody.email) -eq $false)
	{
		$VMs = Get-AzureRmResource -TagName "int_owner" -TagValue $webhookbody.email -ResourceType Microsoft.Compute/virtualMachines
	}
	else
	{
		Write-Output "email empty, breaking"
		break
	}
	# Filter Allowed to automate and user VMs
	$FilteredOutput = @()
	foreach ($b in $VMs)
	{
		$AutomateTags = $b.Tags["int_automate"] | ConvertFrom-VMTagJSON
		if (($AutomateTags.int_allow_automate -eq 'true') -and ($b.tags['int_vm_type'] -eq 'user'))
		{
			$FilteredOutput += $b
		}
	}
}

# Email Splat

$EmailSplat = @{
	'SMTPServer' = 'smtp.office365.com';
	'To'		 = $webhookbody.email;
	'UseSSL'	 = $true;
	'Port'	     = "587";
	'From'	     = "Start My VM <smvm@Squaredup.com>";
	'BodyAsHtml' = $true;
	'Credential' = $Cred
}

if ([system.String]::IsNullOrEmpty($FilteredOutput) -eq $false)
{
	foreach ($a in $FilteredOutput)
	{
		$VM = Get-AzureRMVM -Name $a.Name -ResourceGroupName $a.ResourceGroupName -Status
		$Fail = $HtmlFail.Replace('{0}', $($VM.Name))
		$Fail = $Fail.Replace('{2}', $(Get-Random -InputObject $FailedGifs))
		$Success = $HtmlSuccess.Replace('{0}', $($VM.Name))
		$Success = $Success.Replace('{2}', $(Get-Random -InputObject $SuccessGifs))
		if ((($VM.Statuses | where code -Like "PowerState*").DisplayStatus -eq "VM deallocated") -or (($VM.Statuses | where code -Like "PowerState*").DisplayStatus -eq "VM stopped"))
		{
			try
			{
				Write-Output "Starting $($VM.Name).."
				$null = Start-AzureRMVM -Name $($VM.Name) -ResourceGroupName $($VM.ResourceGroupName)
				Write-Output "VM $($VM.Name) started!"
				if (($email) -and ([System.String]::IsNullOrEmpty($webhookbody.response_url)))
				{
					Send-MailMessage @EmailSplat -Subject "[Success] Started $($VM.Name) Successfully!" -Body $Success
				}
				if ([System.String]::IsNullOrEmpty($webhookbody.response_url) -eq $false)
				{
					$JSON = @{
						"response_type" = "ephemeral";
						"username"	    = "Start My VM";
						"text"		    = "Started VM _*$($a.Name)*_, go you!";
						"mrkdwn"	    = $true						
					}
					Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
				}
			}
			Catch
			{
				$Fail = $Fail.Replace('{1}', $($_.Exception.Message))
				Write-Output "Failed to start VM $($VM.Name)"

				if (($email) -and ([System.String]::IsNullOrEmpty($webhookbody.response_url)))
				{
					Send-MailMessage @EmailSplat -Subject "[Failure] Failed to Start $($VM.Name)" -Body $Fail
				}
				if ([System.String]::IsNullOrEmpty($webhookbody.response_url) -eq $false)
				{
					$JSON = @{
						"response_type" = "ephemeral";
						"username"	    = "Start My VM";
						"text"		    = "Failed to start VM _*$($a.Name)*_.. Exception: $($_.Exception.Message)";
						"mrkdwn"	    = $true
					}
					Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
				}
			}
		}
		else
		{
			Write-Output "Failed to start VM, its current state is $(($VM.Statuses | where code -Like "PowerState*").DisplayStatus)"

			if (($email) -and ([System.String]::IsNullOrEmpty($webhookbody.response_url)))
			{
				Send-MailMessage @EmailSplat -Subject "[Warning] Failed to Start $($VM.Name)" -Body $Fail
			}
			if ([System.String]::IsNullOrEmpty($webhookbody.response_url) -eq $false)
			{
				$JSON = @{
					"response_type" = "ephemeral";					
					"username"	    = "Start My VM";
					"text"		    = "Failed to start VM _*$($a.Name)*_ it's currently in state _$(($VM.Statuses | where code -Like "PowerState*").DisplayStatus)_.";
					"mrkdwn"	    = $true
				}
				Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
			}
		}
	}
}
else
{
	if (($email) -and ([System.String]::IsNullOrEmpty($webhookbody.response_url)))
	{
		$Warning = $HtmlWarning.Replace('{2}', $(Get-Random -InputObject $WarningGifs))
		Send-MailMessage @EmailSplat -Subject "[Warning] No VMs to Start" -Body $HtmlWarning
	}
	if ([System.String]::IsNullOrEmpty($webhookbody.response_url) -eq $false)
	{
		$JSON = @{
			"response_type" = "ephemeral";
			"username"	    = "Start My VM";
			"text"		    = "Looks like you're not the owner of any VMs, so naturally we had nothing to start!";
			"mrkdwn"	    = $true
		}
		Invoke-WebRequest -UseBasicParsing -Method Post -Body $(ConvertTo-Json $JSON) -ContentType "application/json" -Uri $webhookbody.response_url
	}
	Write-Output "The VMs you're the owner of are either set to 'int_allowed_automate = false' or you're not set as an owner of any VMs, breaking."
	break
}