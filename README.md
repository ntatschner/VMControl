# VMControl
Source for Azure Automation Account Runbooks to control dev VMs from Slack

Relies on VM tags:
one of them uses nested JSON with tag/value as below :
 int_automate : {"int_auto_weekday":"schedule","int_allow_automate":"true","int_auto_schedule_slot":"06:00-18:00","int_auto_weekend":"off","int_automate_postpone":"false"}
 
int_vm_type : user
This needs to be set as user so nothing else is automated

int_owner : EMAILADDRESS
This is the email address of the user who owns the VM

int_slack_userid : SLACKID

This is added when using the /verifymyvm command#

The following commands need to be created in slack:

/startmyvm

Starts your Azure User VM

/verifymyvm

VM Owner Verification

/getmyvm

Gets some details about your user VM

/automatemyvm

Enable or Disable VM Automation on your user VMs, enter "enable" or "disable" as desired.

/stopmyvm

Stops the references VMs, if you're the owner and they are user VMs.

/schedulemyvm

Get or Sets your VM automation schedule

and the webhook needs to be pointed to the Microsoft Flow commands.

The Flow commands need to be then pointed to webhooks on the Azure Runbooks
