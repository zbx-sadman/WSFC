<#                                          
Microsoft Server Failover Cluster's Miner
Version 0.9
zbx.sadman@gmail.com (c) 2016
https://github.com/zbx-sadman
#>

Param (
[string]$Action,
[string]$Cluster,
[string]$Object,
[string]$Key,
[string]$Id,
[string]$consoleCP,
[switch]$defaultConsoleWidth
)

[System.Threading.Thread]::CurrentThread.CurrentCulture = "en-US"

Set-Variable -Name "RES_VM" -Value 'Virtual Machine' -Option Constant -Scope Global
Set-Variable -Name "RES_GS" -Value 'Generic Service' -Option Constant -Scope Global
Set-Variable -Name "NS_HYPERV" -Value 'root\virtualization' -Option Constant -Scope Global

filter IDEqualOrAny($Id) { if (($_.Id -Eq $Id) -Or (!$Id)) { $_ } }

Function Prepare-ToLLD {
  Param (
           [Parameter(Mandatory = $true, ValueFromPipeline = $true)] 
           [PSObject]$InObject
        );
  $InObject = ($InObject.ToString());
  $InObject.Replace("`"", "\`"");
}

function ConvertTo-Encoding ([string]$From, [string]$To){  
    Begin   {  
        $encFrom = [System.Text.Encoding]::GetEncoding($from)  
        $encTo = [System.Text.Encoding]::GetEncoding($to)  
    }  
    Process {  
        $bytes = $encTo.GetBytes($_)  
        $bytes = [System.Text.Encoding]::Convert($encFrom, $encTo, $bytes)  
        $encTo.GetString($bytes)  
    }  
}

Function Get-Metric { 
  Param ([PSObject]$InObject, [array]$Keys);

  if ('ClusterParameter' -eq $Keys[0]) {
     if ($Keys[1]) {
        $InObject = ($InObject | Get-ClusterParameter $Keys[1]).Value;
     } else {
        $InObject = $InObject | Get-ClusterParameter ;
     }
  } else {
     $Keys | % { if ($_) { $InObject = $InObject | Select -Expand $_ }};
  }
  $InObject;
}

Function Get-ClusterResourceList { 
  Param (
           [Parameter(Mandatory = $true, ValueFromPipeline = $true)] 
           [PSObject]$InObject, 
           [string]$ResourceType
        );
  # Get all Resources with some type that related to InObject or just copy item if InObject already contain Resources
  $Result = $InObject | % { if ( $_.ResourceType ) { $_ } else { $_ | Get-ClusterResource }} | ? {$ResourceType -eq $_.ResourceType}; 
  if ($Result) {
     switch ($ResourceType) {
        $RES_VM  {  
                   # Force push VmID to list
                   $Result | % { $_ | Add-Member -Force -MemberType NoteProperty -Name "VmID" -Value ($_ | Get-ClusterParameter VmID).Value; }
                 }
       }
  }
  # Return Resource list
  $Result;
}

Function How-Much { 
   Begin   { $Result = 0; }  
   Process { if ($_) { $Result++; } }  
   End     { $Result; }
}

Function ConvertTo-UnixTime { 
    Begin   { $StartDate = Get-Date -Date "01/01/1970"; }  
    Process { (New-TimeSpan -Start $StartDate -End $_).TotalSeconds; }  
}

Function Make-JSON {
  Param ([PSObject]$InObject, [array]$ObjectProperties, [switch]$Pretty);
  # Pretty json contain spaces, tabs and new-lines
  if ($Pretty) { $CRLF = "`n"; $Tab = "    "; $Space = " "; } else {$CRLF = $Tab = $Space = "";}
  # Init JSON-string $InObject
  $Result += "{$CRLF$Space`"data`":[$CRLF";
  # Take each Item from $InObject, get Properties that equal $ObjectProperties items and make JSON from its
  $itFirstObject = $True;
  ForEach ($Object in $InObject) {
     if (-Not $itFirstObject) { $Result += ",$CRLF"; }
     $itFirstObject=$False;
     $Result += "$Tab$Tab{$Space"; 
     $itFirstProperty = $True;
     # Process properties. No comma printed after last item
     ForEach ($Property in $ObjectProperties) {
        if (-Not $itFirstProperty) { $Result += ",$Space" }
        $itFirstProperty = $False;
        $Result += "`"{#$Property}`":$Space`"$($Object.$Property | Prepare-ToLLD)`""
     }
     # No comma printed after last string
     $Result += "$Space}";
  }
  # Finalize and return JSON
  "$Result$CRLF$Tab]$CRLF}";
}

Function Get-MsvmSummaryInformation { 
  Param (
         [Parameter(Mandatory = $true, ValueFromPipeline = $true)] 
         [PSObject]$inObject, 
         [Parameter(Mandatory = $true)] 
         [string]$ResourceType
        ); 
  # Get list of 'VM' cluster resources related to Object (Cluster, Clusternode, one VM)
  # if 'ResourceType' prop is exist - object already ClusterResource 
  $Result = @();
  if (!$inObject) { return $Result; }
  $Resources = $inObject | % { if ($_.ResourceType) { $_ } else { $_ | Get-ClusterResourceList -ResourceType $ResourceType }}
  if (!$Resources) { return $Result; }
  $Nodes = $Resources | % {$_.OwnerNode} | Select-Object -Unique
  ForEach ($Node in $Nodes) {
     $VSMgtSvc = Get-WmiObject -ComputerName $Node -NameSpace $NS_HYPERV -Class 'MsVM_virtualSystemManagementService'
     # take only current Node's Resources
     $NodeResources = $Resources | ? { $_.OwnerNode.Id -eq $Node.Id }
     switch ($ResourceType) {
        $RES_VM  {
                    # Make array of $VmSettings.__Paths. Valid for WS2008 R2 SP1 at least
                    $VMSettingPaths = $NodeResources | % { "\\$($_.OwnerNode)\$($NS_HYPERV):Msvm_VirtualSystemSettingData.InstanceID=`"Microsoft:$($_.VmID)`""}
                    # Get bunch of SummaryInformation objects related to VM's which paths contains in $VMSettingPaths
                    # See https://msdn.microsoft.com/en-us/library/cc160706(v=vs.85).aspx to form Information block with @(0,1,4,101,103,...)
                    $NodeVMsSummaryInformation = $VSMgtSvc.GetSummaryInformation( $VMSettingPaths ,  @(0,1,2,4,100,101,103,104,105,106,109,110,112,113))
                    if ( 0 -eq $NodeVMsSummaryInformation.ReturnValue ) { $Result += $NodeVMsSummaryInformation; }
                 }
     } # switch
  } # Foreach
  $Result
}

# Import the cmdlets
Import-Module FailoverClusters

if ($Cluster -eq '') 
   { $objCluster = Get-Cluster | Select-Object -First 1 }
else
   { $objCluster = Get-Cluster -Name $Cluster }

#"Work with: $($objCluster.Name)`nAction: $Action, Object: $Object";
                                   
# if needProcess is False - $Result is not need to convert to string and etc 
$needProcess = $True;
$Keys = $Key.split(".");

# Prepare object lists

switch ($Object) {
     'Cluster'                       { $Objects = $objCluster | IDEqualOrAny $Id; }
     'ClusterNode'                   { $Objects = $objCluster | Get-ClusterNode | IDEqualOrAny $Id; }
     'ClusterNetwork' 	             { $Objects = $objCluster | Get-ClusterNetwork | IDEqualOrAny $Id; }
     'ClusterAvailableDisk'          { $Objects = $objCluster | Get-ClusterAvailableDisk | IDEqualOrAny $Id; }
     'ClusterResourceGenericService' { $Objects = $objCluster | Get-ClusterResourceList -ResourceType $RES_GS | IDEqualOrAny $Id; }
     'ClusterResourceVirtualMachine' { $Objects = $objCluster | Get-ClusterResourceList -ResourceType $RES_VM | IDEqualOrAny $Id; }
     'ClusterSharedVolume'           {
                                       $Objects = $objCluster | Get-ClusterSharedVolume | IDEqualOrAny $Id; 
                                       $Objects | Add-Member -MemberType NoteProperty -Name "Cluster" -Value $objCluster.Name;
                                       $Objects | % { $_ | Add-Member -MemberType NoteProperty -Name "FriendlyVolumeName" -Value ($_ | Select -Expand SharedVolumeInfo  | Select -Expand FriendlyVolumeName) };
                                     }
} # switch ($Object)

switch ($Keys[0]) {
   'VirtualMachine' {
                           switch ($Keys[1]) {
                              'SummaryInformation' { $Objects = $Objects | Get-MsvmSummaryInformation -ResourceType $RES_VM; }
                              'Online'             { $Objects = $Objects | Get-ClusterResourceList -ResourceType $RES_VM | ? { 'online'         -eq $_.State }}
                              'Offline'            { $Objects = $Objects | Get-ClusterResourceList -ResourceType $RES_VM | ? { 'offline'        -eq $_.State }}
                              'OnlinePending'      { $Objects = $Objects | Get-ClusterResourceList -ResourceType $RES_VM | ? { 'onlinepending'  -eq $_.State }}
                              'OfflinePending'     { $Objects = $Objects | Get-ClusterResourceList -ResourceType $RES_VM | ? { 'offlinepending' -eq $_.State }}
                           }
                           $Keys[0] = '';
                    }
   'GenericService' {
                           switch ($Keys[1]) {
                              'Online'             { $Objects = $Objects | Get-ClusterResourceList -ResourceType $RES_GS | ? { 'online'         -eq $_.State }}
                              'Offline'            { $Objects = $Objects | Get-ClusterResourceList -ResourceType $RES_GS | ? { 'offline'        -eq $_.State }}
                           }
                           $Keys[0] = '';
                    }
}

switch ($Action) {
   'Discovery'   {
                   switch ($Object) {
                      'Cluster'                       { $ObjectProperties = @("ID", "NAME"); }
                      'ClusterNode'                   { $ObjectProperties = @("ID", "CLUSTER", "NAME", "STATE"); }
                      'ClusterNetwork'  	      { $ObjectProperties = @("ID", "CLUSTER", "NAME", "STATE", "ROLE"); }
                      'ClusterAvailableDisk'          { $ObjectProperties = @("ID", "CLUSTER", "NAME", "STATE", "ROLE"); }
                      'ClusterResourceGenericService' { $ObjectProperties = @("ID", "CLUSTER", "OWNERNODE", "NAME", "STATE"); }
                      'ClusterResourceVirtualMachine' { $ObjectProperties = @("ID", "CLUSTER", "OWNERNODE", "NAME", "STATE"); }
                      'ClusterSharedVolume'           { $ObjectProperties = @("ID", "CLUSTER", "NAME", "STATE", "FRIENDLYVOLUMENAME"); }
                      default                         { $needProcess = $False; $Result = "Incorrect object: '$Object' for action Discovery";}
                    }  
                    if ($needProcess) { $Result = Make-JSON -InObject $Objects -ObjectProperties $ObjectProperties -Pretty; }
                 }
   'Get'         { if ($Keys) { $Result = Get-Metric -InObject $Objects -Keys $Keys } else { $Result = ($Objects | fl *)}; }
                 # Get-Metric can return an array of objects. In this case need to take each item and add its to $r
   'Sum'         { $Result = $Objects | % { $r = 0 } { (Get-Metric -InObject $_ -Keys $Keys) | % { $r += $_} } { $r }; }
   'Count'       { $Result = $Objects | How-Much; }
   #
   # Error
   #
   default  { $Result = "Incorrect action: '$Action'"; }
}  

# if ('DateTime' -eq $Result.GetType()) {$Result = $Result | Convert-ToUnixTime;}

# Normalize String object
$Result = ($Result | Out-String).Trim();

# Convert String to UTF-8 if need (For Zabbix LLD-JSON with Cyrillic for example)
if ($consoleCP) { $Result = $Result | ConvertTo-Encoding -From $consoleCP -To UTF-8 }

# Break lines on console output fix - buffer format to 255 chars width lines 
if (!$defaultConsoleWidth) { mode con cols=255 }

$Result;
