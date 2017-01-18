#Requires -Modules VMware.VimAutomation.Core

#Connect to vCenter
$user = "service.vra"
$pwd = Get-Content "C:\Scripts\VMware\Credential.txt"
$vcenter = "vswcrpvmwvc01"
$securepwd = $pwd | ConvertTo-SecureString
$credObject = New-Object System.Management.Automation.PSCredential -ArgumentList $user, $securePwd

Connect-VIServer -Server $vcenter -Credential $credObject


function Get-SnapshotCreator {
<# 
     .SYNOPSIS 
     Function to retrieve the creator of a vSphere Snapshot. 
      
     .DESCRIPTION 
     Function to retrieve the creator of a vSphere Snapshot. 
      
     .PARAMETER Snapshot 
     Snapshot to find the creator for 
  
     .INPUTS 
     VMware.VimAutomation.ViCore.Impl.V1.VM.SnapshotImpl. 
  
     .OUTPUTS 
     System.Management.Automation.PSObject. 
  
     .EXAMPLE 
     PS> Get-SnapshotCreator -Snapshot (Get-VM Test01 | Get-Snapshot) 
      
     .EXAMPLE 
     PS> Get-VM Test01 | Get-Snapshot | Get-SnapshotCreator 
 #>
[CmdletBinding()][OutputType('System.Management.Automation.PSObject')]

    Param
    (

    [parameter(Mandatory=$true,ValueFromPipeline=$true)]
    [ValidateNotNullOrEmpty()]
    [VMware.VimAutomation.ViCore.Impl.V1.VM.SnapshotImpl[]]$Snapshot   
    )    

    begin {
    
        $SnapshotCreatorObject = @()

        $TaskMgr = Get-View TaskManager
    }
    
    process {    

        try {
            
            foreach ($Snap in $Snapshot){
         
                # --- Create a filter for the task collector
                $Filter = New-Object VMware.Vim.TaskFilterSpec
                $Filter.Time = New-Object VMware.Vim.TaskFilterSpecByTime
                $Filter.Time.BeginTime = ((($Snap.Created).AddSeconds(-20)).ToUniversalTime())
                $Filter.Time.TimeType = "startedTime"
                $Filter.Time.EndTime = ((($Snap.Created).AddSeconds(20)).ToUniversalTime())
                $Filter.State = "success"
                $Filter.Entity = New-Object VMware.Vim.TaskFilterSpecByEntity
                $Filter.Entity.recursion = "self"
                $Filter.Entity.entity = (Get-VM -Id $Snap.VMId).Extensiondata.MoRef

                # --- Get the task that matches the filter
                $TaskCollector = Get-View ($TaskMgr.CreateCollectorForTasks($Filter))

                # --- Rewind the collector view back to the top
                $TaskCollector.RewindCollector | Out-Null

                # --- Read 1000 events from that point
                $Tasks = $TaskCollector.ReadNextTasks(1000)

                # --- Find the creator
                if ($Tasks){
                    foreach ($Task in $Tasks){

                        $GuestName = $Snap.VM
                        $Task = $Task | Where-Object {$_.DescriptionId -eq "VirtualMachine.createSnapshot" -and $_.State -eq "success" -and $_.EntityName -eq $GuestName}

                        if ($Task){

                            $Creator = $Task.Reason.UserName
                        }
                        else {
                            $Creator = "Unable to Snapshot VM creator"
                        }
                    }
                }
                else {
                    $Creator = "Unable to find Snapshot creator"                        
                }

                # --- Remove the TaskCollector since there is a limit of 32 active collectors
                $TaskCollector.DestroyCollector()
                
                $Object = [pscustomobject]@{                        
                    
                    VM = $Snapshot.VM.Name
                    Snapshot = $Snapshot.Name
#					Desc = $Snapshot.Description
					Created = $Snapshot.Created
#					Size = $Snapshot.SizeGB
                    Creator = $Creator					
                }
                
                $SnapshotCreatorObject += $Object
            }
        }
        catch [Exception]{
        
            throw "Unable to retrieve snapshot creator"
        }    
    }
    end {
        Write-Output $SnapshotCreatorObject
    }
}

#Format email for html and table

$head=@"
<style>
@charset "UTF-8";

table
{
font-family:"Trebuchet MS", Arial, Helvetica, sans-serif;
border-collapse:collapse;
}
td 
{
font-size:1em;
border:1px solid #98bf21;
padding:5px 5px 5px 5px;
}
th 
{
font-size:1.1em;
text-align:center;
padding-top:5px;
padding-bottom:5px;
padding-right:7px;
padding-left:7px;
background-color:#A7C942;
color:#ffffff;
}
name tr
{
color:#F00000;
background-color:#EAF2D3;
}
</style>
"@

#Email creation and sending information

$report = Get-VM | Get-Snapshot | Get-SnapshotCreator | Where {$_.Created -lt ((Get-Date).AddDays(-7))} | ConvertTo-Html -Head $head -PreContent "<H2>Snapshot Report: > 7 Days</H2>" | Out-String
$smtpServer = "webmail.allegiantair.com"
$msg = new-object Net.Mail.MailMessage
$smtp = new-object Net.Mail.SmtpClient($smtpServer)
$msg.From = "vROnotifiations@allegiantair.com"
$msg.To.Add("DEP_Data_Center_Virtualization@allegiantair.com")
$msg.Subject = "VSWCRPVMWVC01 Snapshots Older Than 7 Days Report"
$msg.IsBodyHTML = $true
$msg.Body = $report
$smtp.Send($msg)
