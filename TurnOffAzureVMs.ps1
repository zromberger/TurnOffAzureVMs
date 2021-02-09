#3rd time's a charm. Maybe.

$Servers = @(
    "<list your>"
    "<servers here>"
    "<like this>"
)

#how many machines do you want the script to leave running?
$leaveRunning = 1

#mail
$From = "<email to send notifications>"
$password = '<password to email to send notifications>' |  Convertto-SecureString -AsPlainText -Force																		   
$To = "<where to send the email to get notifications>"
$Body = ""
$SMTPServer = "<your email providers SMTP>"
$SMTPPort = 587
$emailcredentials = New-Object -TypeName System.Management.Automation.Pscredential -Argumentlist $from, $password
$subject = ""


# Setup credentials
$AzureAdminUser = '<your service account>'
$AzureAdminPassword = '<your service account password>'									
$AzureAdminPassword = ConvertTo-SecureString -AsPlainText $AzureAdminPassword -Force
$AzureAdminCredentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AzureAdminUser, $AzureAdminPassword
$AzureResourceGroup = "<your resource group>"

#----------------------------------------------------

Import-Module -Name AzureRM.Compute
Connect-AzureRmAccount -Credential $AzureAdminCredentials

$stoppedServers = 0

[System.Collections.ArrayList]$runningServers = @()

[System.Collections.ArrayList]$Sessions = @()

$body += "--Query Stage--`n"

foreach ($server in $Servers)  {
$serverstate = ((Get-AzureRMVM -Status -ResourceGroupName $AzureResourceGroup -Name $server).Statuses).code[1]
    if($serverstate -like "*deallocated"){
        #debug
        #write-host "off"
        $body += "$server is deallocated. Skipping query stage...`n"
		$stoppedServers += 1
    }
    elseif($serverstate -like "*running"){
        #debug
        #write-host "on"
        $body += "$server is running. Querying for active users...`n"
        $runningServers.Add($server);
    } else {
        $subject += "ERROR! "
        $body += "ERROR: Server isn't deallocated or running. Outputting Status.`n$serverstate`n"
    }
}

#----------------------------------------------------

#the beauty of using quser like this is that errors work to my advantage :)
 
$body += "--User Log--`n"

#Go through each server
foreach ($Server in $runningServers)  {
	#Get the current sessions on $Server and also format the output
	$DirtyOuput = (quser /server:$Server) -replace '\s{2,}', ',' | ConvertFrom-Csv
	
	#Go through each session in $DirtyOuput
	foreach ($session in $DirtyOuput) {
	#Initialize a temporary hash where we will store the data
	$tmpHash = @{}

	    #Check if SESSIONNAME isn't like "console" and isn't like "rdp-tcp*"
	    if (($session.sessionname -notlike "console") -AND ($session.sessionname -notlike "rdp-tcp*")) {
		    #if the script is in here, the values are shifted and we need to match them correctly
		    $tmpHash = @{
		        Username = $session.USERNAME
		        SessionName = "" #Session name is empty in this case
		        ID = $session.SESSIONNAME
		        State = $session.ID
		        IdleTime = $session.STATE
		        LogonTime = $session."IDLE TIME"
		        ServerName = $Server
		    }
	    } else {
		    #if the script is in here, it means that the values are correct
		    $tmpHash = @{
		        Username = $session.USERNAME
		        SessionName = $session.SESSIONNAME
		        ID = $session.ID
		        State = $session.STATE
		        IdleTime = $session."IDLE TIME"
		        LogonTime = $session."LOGON TIME"
		        ServerName = $Server
		    }
	    }       
		#Add the hash to $Sessions
		$Sessions.Add((New-Object PSObject -Property $tmpHash)) | Out-Null
 
    }
}

#----------------------------------------------------

foreach($server in $runningServers) {
        #counters for the loop logic
        $SessionCount = 0
        $DiscSession = 0
        $Body += "-$($server)-`n"
    foreach($session in $sessions) {
        #since the sessions are all in one hashtable;
        #go through them and find the ones that match the server we're processing and count them
        if ($session.ServerName -eq $server) {
            $SessionCount += 1
            $body += $session.USERNAME + "   " + $session.state +"`n"
        }
        #count the disconnected sessions
        if ($session.state -eq 'Disc' -AND $session.ServerName -eq $server) {
            $DiscSession += 1
        }
    }
    #compare the disconnected sessions to the total number of sessions
    if ($SessionCount -eq $DiscSession) {
        #this determines if the server should be stopped
        if ($stoppedServers -ge $Servers.count - $leaveRunning) {
            $body += "No one is connected to: $server. This server will stay running as the others have been stopped.`n"
        }
        if ($stoppedServers -lt $Servers.count - $leaveRunning) {
            #servers that meet all of the critera will be stopped!
            Stop-AzureRMVM -ResourceGroupName $AzureResourceGroup -Name $server -Force
            $stoppedServers += 1
            $body += "No one is connected to: $server. The server has been stopped.`n"
            #debug
            #Write-Host "stoppedservers: $stoppedServers -- servers.count: $($servers.count)"
        }
    } else {
        $body += "Users are still connected to: $server`n"
        #debug
        #Write-Host "no stop $server"
    }
}

#date&time here, to determine script run time

$date = Get-Date -UFormat "%A, %D - %r"
$subject += "Azure Turn Off Report: $date"

Send-MailMessage -UseSsl -From $From -To $To -Subject $Subject -Body $Body `
    -SmtpServer $SMTPServer -port $SMTPPort -Credential ($emailcredentials) `
    –DeliveryNotificationOption OnSuccess

#debug, prints all the sessions
#$Sessions | Sort-Object -Property servername | Select-Object -Property Username, state, ServerName | Format-Table