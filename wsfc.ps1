<#                                          
    .SYNOPSIS  
        Return Microsoft Server Failover Cluster's metrics value, sum & count selected objects, make LLD-JSON for Zabbix

    .DESCRIPTION
        Return Microsoft Server Failover Cluster's metrics value, sum & count selected objects, make LLD-JSON for Zabbix

    .NOTES  
        Version: 1.2.0
        Name: WSFC Miner
        Author: zbx.sadman@gmail.com
        DateCreated: 23MAR2016
        Testing environment: Windows Server 2008R2 SP1, Powershell 2.0
        Non-production testing environment: Windows Server 2012 R2, PowerShell 4

    .LINK  
        https://github.com/zbx-sadman

    .PARAMETER Action
        What need to do with collection or its item:
            Discovery - Make Zabbix's LLD JSON;
            Get       - Get metric from collection item;
            Sum       - Sum metrics of collection items;
            Count     - Count collection items.

    .PARAMETER ObjectType
        Define rule to make collection:
            Cluster   - failover cluster;
            ClusterNode - failover cluster's node;
            ClusterNetwork - failover cluster's network;
            ClusterNetworkInterface - failover cluster's network adapter;
            ClusterResourceDHCPService - failover cluster's resource 'DHCP Service';
            ClusterResourceGenericService - failover cluster's resource 'Generic Service';
            ClusterResourceVirtualMachine - failover cluster's resource 'Virtual Machine';
            ClusterResourceVirtualMachineConfiguration - failover cluster's resource 'Virtual Machine Configuration';
            ClusterResourceIPAddress - failover cluster's resource 'IP Address';
            ClusterResourceNetworkName - failover cluster's resource 'Network Name';
            ClusterResourcePhysicalDisk - failover cluster's resource 'Physical Disk';
            ClusterAvailableDisk - failover cluster's disks that can support Failover Clustering and are visible to all nodes, but are not yet part of the set of clustered disks.
            ClusterSharedVolume - failover cluster's Cluster Shared Volume;
            ClusterQuorum - failover cluster's quorum;

    .PARAMETER Key
        Define "path" to collection item's metric 

        Virtual keys for 'Cluster', 'ClusterNode' objects:
            VirtualMachine.Online - failover cluster's resource 'Virtual Machine' in Online state;
            VirtualMachine.Offline - ... in Offline state;
            VirtualMachine.OnlinePending  - ... in OnlinePending state;
            VirtualMachine.OfflinePending - ... in OfflinePending state;
            VirtualMachine.SummaryInformation - set of metrics related to cluster resource 'Virtual Machine' and fetched from MsVM_virtualSystemManagementService class with WMI-query
            GenericService.Online  - failover cluster's resource 'Generic Service' in Online state;
            GenericService.Offline - ... in Offline state;

        Virtual keys for all object which linked to private cluster objects properties (see Get-ClusterParameter cmdlet)
            ClusterParameter.<metric> - private cluster object's metric

    .PARAMETER ID
        Used to select only one item from collection

    .PARAMETER ErrorCode
        What must be returned if any process error will be reached

    .PARAMETER ConsoleCP
        Codepage of Windows console. Need to properly convert output to UTF-8

    .PARAMETER DefaultConsoleWidth
        Say to leave default console width and not grow its to $CONSOLE_WIDTH

    .PARAMETER Verbose
        Enable verbose messages

    .EXAMPLE 
        powershell.exe -NoProfile -ExecutionPolicy "RemoteSigned" -File "wsfc.ps1" -Action "Discovery" -ObjectType "ClusterResourceVirtualMachine"

        Description
        -----------  
        Make Zabbix's LLD JSON for Virtual Machines in failover cluster(s)

    .EXAMPLE 
        ... "wsfc.ps1" -Action "Count" -ObjectType "ClusterNode" -Key "VirtualMachine.Online" -Id "00000000-0000-0000-0000-000000000002" -consoleCP CP866

        Description
        -----------  
        Return number of online Virtual Machines owned by cluster node with id="00000000-0000-0000-0000-000000000002". 
        All Russian Cyrillic sybbols in VM's names (for example) will be converted to UTF-8.


    .EXAMPLE 
        ... "wsfc.ps1" -Action "Sum" -ObjectType "Cluster" -Key "VirtualMachine.SummaryInformation.MemoryUsage" -Id "f4479814-35d4-41c5-babd-c0697769ac31"

        Description
        -----------  
        Return memory size that assigned to (used by) Virtual Machines owned by whole cluster with id="f4479814-35d4-41c5-babd-c0697769ac31"

    .EXAMPLE 
        ... "wsfc.ps1" -Action "Get" -ObjectType "ClusterSharedVolume" -Key "SharedVolumeInfo.Partition" -ID "8e8fb118-2601-4a06-ab9a-f0a1260bd247" -DefaultConsoleWidth -Verbose

        Description
        -----------  
        Show formatted list of 'ClusterSharedVolume' object metrics accessed with property 'SharedVolumeInfo.Partition'.
        Verbose messages is enabled. 

#>


Param (
   [Parameter(Mandatory = $False)] 
   [ValidateSet('Discovery','Get','Count', 'Sum')]
   [String]$Action,
   [String]$ClusterName,
   [Parameter(Mandatory = $False)]
   [ValidateSet('Cluster', 'ClusterNode', 'ClusterNetwork', 'ClusterNetworkInterface', 'ClusterResourceDHCPService', 'ClusterResourceGenericService', 
                'ClusterResourceVirtualMachine', 'ClusterResourceVirtualMachineConfiguration', 'ClusterResourceNetworkName', 'ClusterResourceIPAddress', 
                'ClusterResourcePhysicalDisk', 'ClusterAvailableDisk', 'ClusterSharedVolume')]
   [Alias('Object')]
   [String]$ObjectType,
   [Parameter(Mandatory = $False)]
   [String]$Key,
   [Parameter(Mandatory = $False)]
   [String]$Id,
   [Parameter(Mandatory = $False)]
   [String]$ErrorCode,
   [Parameter(Mandatory = $False)]
   [String]$ConsoleCP,
   [Parameter(Mandatory = $False)]
   [Switch]$DefaultConsoleWidth
);

#Set-StrictMode -Version Latest

# Set US locale to properly formatting float numbers while converting to string
[System.Threading.Thread]::CurrentThread.CurrentCulture = "en-US"
# Width of console to stop breaking JSON lines
Set-Variable -Option Constant -Name "CONSOLE_WIDTH" -Value 512

Set-Variable -Option Constant -Name "RES_DHCPS"  -Value 'DHCP Service'
Set-Variable -Option Constant -Name "RES_VM"  -Value 'Virtual Machine'
Set-Variable -Option Constant -Name "RES_GS"  -Value 'Generic Service'
Set-Variable -Option Constant -Name "RES_PD"  -Value 'Physical Disk'
Set-Variable -Option Constant -Name "RES_NN"  -Value 'Network Name'
Set-Variable -Option Constant -Name "RES_IA"  -Value 'IP Address'
Set-Variable -Option Constant -Name "RES_VMC" -Value 'Virtual Machine Configuration'

# Enumerate OS versions. [int][OSVersions]::DumpVer equal 0 due [int][OSVersions]::AnyNonexistItem equal 0 too
#Add-Type -TypeDefinition "public enum OSVersion { DumpVer, WS2008, WS2008R2, WS2012, WS2012R2}";
Add-Type -TypeDefinition "public enum OSVersion { DumpVer, v60, v61, v62, v63}";

####################################################################################################################################
#
#                                                  Function block
#    
####################################################################################################################################
#
#  Select object with Property that equal Value if its given or with Any Property in another case
#
Function PropertyEqualOrAny {
   Param (
      [Parameter(ValueFromPipeline = $True)] 
      [PSObject]$InputObject,
      [PSObject]$Property,
      [PSObject]$Value
   );
   Process {
      # Do something with all objects (non-pipelined input case)  
      ForEach ($Object in $InputObject) { 
         # IsNullorEmpty used because !$Value give a erong result with $Value = 0 (True).
         # But 0 may be right ID  
         If (($Object.$Property -Eq $Value) -Or ([string]::IsNullorEmpty($Value))) { $Object }
      }
   } 
}

#
#  Prepare string to using with Zabbix 
#
Function PrepareTo-Zabbix {
   Param (
      [Parameter(ValueFromPipeline = $True)] 
      [PSObject]$InputObject,
      [String]$ErrorCode,
      [Switch]$NoEscape,
      [Switch]$JSONCompatible
   );
   Begin {
      # Add here more symbols to escaping if you need
      $EscapedSymbols = @('\', '"');
      $UnixEpoch = Get-Date -Date "01/01/1970";
   }
   Process {
      # Do something with all objects (non-pipelined input case)  
      ForEach ($Object in $InputObject) { 
         If ($Null -Eq $Object) {
           # Put empty string or $ErrorCode to output  
           If ($ErrorCode) { $ErrorCode } Else { "" }
           Continue;
         }
         # Need add doublequote around string for other objects when JSON compatible output requested?
         $DoQuote = $False;
         Switch (($Object.GetType()).FullName) {
            'System.Boolean'  { $Object = [int]$Object; }
            'System.DateTime' { $Object = (New-TimeSpan -Start $UnixEpoch -End $Object).TotalSeconds; }
            Default           { $DoQuote = $True; }
         }
         # Normalize String object
         $Object = $( If ($JSONCompatible) { $Object.ToString().Trim() } else { Out-String -InputObject (Format-List -InputObject $Object -Property *) });         

         If (!$NoEscape) { 
            ForEach ($Symbol in $EscapedSymbols) { 
               $Object = $Object.Replace($Symbol, "\$Symbol");
            }
         }

         # Doublequote object if adherence to JSON standart requested
         If ($JSONCompatible -And $DoQuote) { 
            "`"$Object`"";
         } else {
            $Object;
         }
      }
   }
}

#
#  Convert incoming object's content to UTF-8
#
Function ConvertTo-Encoding ([String]$From, [String]$To){  
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

#
#  Make & return JSON, due PoSh 2.0 haven't Covert-ToJSON
#
Function Make-JSON {
   Param (
      [Parameter(ValueFromPipeline = $True)] 
      [PSObject]$InputObject, 
      [array]$ObjectProperties, 
      [Switch]$Pretty
   ); 
   Begin   {
      [String]$Result = "";
      # Pretty json contain spaces, tabs and new-lines
      If ($Pretty) { $CRLF = "`n"; $Tab = "    "; $Space = " "; } Else { $CRLF = $Tab = $Space = ""; }
      # Init JSON-string $InObject
      $Result += "{$CRLF$Space`"data`":[$CRLF";
      # Take each Item from $InObject, get Properties that equal $ObjectProperties items and make JSON from its
      $itFirstObject = $True;
   } 
   Process {
      # Do something with all objects (non-pipelined input case)  
      ForEach ($Object in $InputObject) {
         # Skip object when its $Null
         If ($Null -Eq $Object) { Continue; }
         If (-Not $itFirstObject) { $Result += ",$CRLF"; }
         $itFirstObject=$False;
         $Result += "$Tab$Tab{$Space"; 
         $itFirstProperty = $True;
         # Process properties. No comma printed after last item
         ForEach ($Property in $ObjectProperties) {
            If ([string]::IsNullOrEmpty($Object.$Property)) { Continue; }
            If (-Not $itFirstProperty) { $Result += ",$Space" }
            $itFirstProperty = $False;
            $Result += "`"{#$Property}`":$(PrepareTo-Zabbix -InputObject $Object.$Property -JSONCompatible)";
         }
         # No comma printed after last string
         $Result += "$Space}";
      }
   }
   End {
      # Finalize and return JSON
      "$Result$CRLF$Tab]$CRLF}";
   }
}

#
#  Return value of object's metric defined by key-chain from $Keys Array
#
Function Get-Metric { 
   Param (
      [Parameter(ValueFromPipeline = $True)] 
      [PSObject]$InputObject, 
      [Array]$Keys
   ); 
   Process {
      # Do something with all objects (non-pipelined input case)  
      ForEach ($Object in $InputObject) { 
        If ($Null -Eq $Object) { Continue; }
       # Expand all metrics related to keys contained in array step by step
        ForEach ($Key in $Keys) {              
           If ($Key) {
              $Object = Select-Object -InputObject $Object -ExpandProperty $Key -ErrorAction SilentlyContinue;
              If ($Error) { Break; }
           }
        }
        $Object;
      }
   }
}

#
#  Exit with specified ErrorCode or Warning message
#
Function Exit-WithMessage { 
   Param (
      [Parameter(Mandatory = $True, ValueFromPipeline = $True)] 
      [String]$Message, 
      [String]$ErrorCode 
   ); 
   If ($ErrorCode) { 
      $ErrorCode;
   } Else {
      Write-Warning ($Message);
   }
   Exit;
}

Function Get-ClusterResourceList { 
   Param (
      [Parameter(ValueFromPipeline = $True)] 
      [PSObject]$InputObject, 
      [Parameter(Mandatory = $False)] 
      [string]$ResourceType
   ); 
   Process {
      Write-Verbose "$(Get-Date) Going thru object list";
      ForEach ($Object in $InputObject) { 
         If ($Null -Eq $Object) { Continue; }
         Write-Verbose "$(Get-Date) Object $($Object.GetType().Name) $($Object.Name) processeed";
         $ClusterResources = $(
            # Object may be already is Get-ClusterResource with ResourceType property
            if ($Object.ResourceType) { 
               Write-Verbose "$(Get-Date) Going thru object list";
               $Object;
            } else {
               Write-Verbose "$(Get-Date) Taking all ClusterResources for this object";
               Get-ClusterResource -InputObject $Object;
            } 
         ) | Where-Object {$ResourceType -eq $_.ResourceType};
         Write-Verbose "$(Get-Date) ClusterResources is Null? $($Null -Eq $ClusterResources)";
         # Go to next loop if no $ClusterResources found
         if ($Null -Eq $ClusterResources) { Continue; }
         Write-Verbose "$(Get-Date) Process ClusterResources";
     
         # Walk Thru resources
         ForEach ($ClusterResource in $ClusterResources) {
            Switch ($ClusterResource.ResourceType) {
               $RES_VM  {  
                  # Force push VmID property to ClusterResource object if its Virtual Machine
                  Add-Member -InputObject $ClusterResource -Force -MemberType NoteProperty -Name "VmID" -Value (Get-ClusterParameter -InputObject $ClusterResource -Name VmID).Value;
               }
            } 
         } # ForEach ($ClusterResource in $ClusterResources)
         # Return Resource list
         $ClusterResources;
      } # ForEach ($Object in $InputObject)
   }
}

Function Get-MsvmSummaryInformation { 
  Param (
         [Parameter(ValueFromPipeline = $True)] 
         [PSObject]$InputObject, 
         [Parameter(Mandatory = $True)] 
         [string]$ResourceType
        ); 
  # Get list of 'VM' cluster resources related to Object (Cluster, Clusternode, one VM)
  # if 'ResourceType' prop is exist - object already ClusterResource 
  $Result = @();
  # pre-group resources by OwnerNode to make one WMI-query to one Owner for its resources
  $GroupedResources = @{};
  ForEach ($Object in $InputObject) {
     If ($Null -Eq $Object) { Continue; }
     $OwnerNode = $Object.OwnerNode.Name;
     If (!$GroupedResources.ContainsKey($OwnerNode)) { 
        $GroupedResources.Add($OwnerNode, @())
     }
     $GroupedResources.$OwnerNode += $Object;
  
  }
  ForEach ($OwnerNode in $GroupedResources.Keys) {
     If ($Null -Eq $OwnerNode) { Continue; }
     # take only current Node's Resources
     switch ($ResourceType) {
        $RES_VM  {
           $VSMgtSvc = Get-WmiObject -ComputerName $OwnerNode -NameSpace $NS_HYPERV -Class 'MsVM_virtualSystemManagementService'
           # Make array of $VmSettings.__Paths. Valid for WS2008 R2 SP1 at least
           $VMSettingPaths = $(ForEach($VM in @($GroupedResources.$OwnerNode)) { 
              "\\$($OwnerNode)\$($NS_HYPERV):Msvm_VirtualSystemSettingData.InstanceID=`"Microsoft:$($VM.VmID)`"" 
           });
           # Get bunch of SummaryInformation objects related to VM's which paths contains in $VMSettingPaths
           # See https://msdn.microsoft.com/en-us/library/cc160706(v=vs.85).aspx to form Information block with @(0,1,4,101,103,...)
           $NodeVMsSummaryInformation = $VSMgtSvc.GetSummaryInformation( $VMSettingPaths ,  @(0,1,2,4,100,101,103,104,105,106,109,110,112,113))
           if ( 0 -eq $NodeVMsSummaryInformation.ReturnValue ) { $NodeVMsSummaryInformation.SummaryInformation; }
        } # $RES_VM
     } # switch
  } # Foreach
}

Write-Verbose "$(Get-Date) Checking OS Windows version";

$OSVersion = "v$([Environment]::OSVersion.Version.Major)$([Environment]::OSVersion.Version.Minor)"

$OSName = $( Switch ($OSVersion -As [OSVersion]) {
   'v60' { # Windows Vista / Windows Server 2008
       Set-Variable -Option Constant -Name "NS_HYPERV" -Value 'root\virtualization' 
       "Windows Vista / Windows Server 2008"
   }
   'v61' { # Windows 7 / Windows Server 2008 R2
       Set-Variable -Option Constant -Name "NS_HYPERV" -Value 'root\virtualization' 
       "Windows 7 / Windows Server 2008 R2"
   }
   'v62' { # Windows 8 / Windows Server 2012
       Set-Variable -Option Constant -Name "NS_HYPERV" -Value 'root\virtualization\v2' 
       "Windows 8 / Windows Server 2012"
   }
   'v63' { # Windows 8.1 / Windows Server 2012 R2
       Set-Variable -Option Constant -Name "NS_HYPERV" -Value 'root\virtualization\v2' 
       "Windows 8.1 / Windows Server 2012 R2"
   }
   Default { # Incompatible OS version
      Exit-WithMessage -Message "Incompatible OS version" -ErrorCode $ErrorCode;
   }
});

Write-Verbose "$(Get-Date) Work under $OSName";
Write-Verbose "$(Get-Date) Import 'FailoverClusters' module";

# Import the cmdlets
Import-Module -Name FailoverClusters -Verbose:$False -Cmdlet Get-* 

if ([String]::IsNullorEmpty($ClusterName)) { 
   Write-Verbose "$(Get-Date) Try to get clusters";
   $Clusters = Get-Cluster
} else {
   Write-Verbose "$(Get-Date) Try to get '$ClusterName' cluster";
   $Clusters = Get-Cluster -Name $ClusterName
}

If ($Null -Eq $Clusters) {
   Exit-WithMessage -Message "No cluster(s) availabile" -ErrorCode $ErrorCode;
}

$Result = 0;
# split key to subkeys
$Keys = $Key.Split(".");

Write-Verbose "$(Get-Date) Creating collection of specified object: '$ObjectType'";

# Prepare object lists

$Objects = $( ForEach ($Cluster in $Clusters) {  
   If ($Null -Eq $Cluster) { Continue; }
   Switch ($ObjectType) {
     'Cluster' {
         PropertyEqualOrAny -InputObject $Clusters -Property ID -Value $Id;  
     }
     'ClusterNode' { 
         PropertyEqualOrAny -InputObject (Get-ClusterNode -InputObject $Cluster) -Property ID -Value $Id
     }
     'ClusterNetwork' { 
         PropertyEqualOrAny -InputObject (Get-ClusterNetwork -InputObject $Cluster) -Property ID -Value $Id
     }
     'ClusterNetworkInterface' { 
         $ClusterNetworks = Get-ClusterNetwork -InputObject $Cluster;
         $ClusterNetworkInterfaces = $( ForEach ($ClusterNetwork in $ClusterNetworks) {
            If ($Null -Eq $ClusterNetwork) { Continue; }
            ForEach ($ClusterNetworkInterface in (Get-ClusterNetworkInterface -Network $ClusterNetwork.Name)) {
               If ($Null -Eq $ClusterNetworkInterface) { Continue; }
               Add-Member -InputObject $ClusterNetworkInterface -MemberType NoteProperty -Name "NetworkAddress" -Value $ClusterNetwork.Address;
               # Split IPv6 Address & Zone index by % sign
               $Address, $IPv6ZoneIndex = $ClusterNetworkInterface.Address.ToString().Split('%')
               Add-Member -Force -InputObject $ClusterNetworkInterface -MemberType NoteProperty -Name "Address" -Value $Address;
               $ClusterNetworkInterface
           }
         });
         PropertyEqualOrAny -InputObject ($ClusterNetworkInterfaces) -Property ID -Value $Id
     }
     'ClusterResourceDHCPService' { 
         PropertyEqualOrAny -InputObject (Get-ClusterResourceList -InputObject $Cluster -ResourceType $RES_DHCPS) -Property ID -Value $Id
     }
     'ClusterResourceGenericService' { 
         PropertyEqualOrAny -InputObject (Get-ClusterResourceList -InputObject $Cluster -ResourceType $RES_GS) -Property ID -Value $Id
     }
     'ClusterResourceVirtualMachine' {
         PropertyEqualOrAny -InputObject (Get-ClusterResourceList -InputObject $Cluster -ResourceType $RES_VM) -Property ID -Value $Id
     }
     'ClusterResourcePhysicalDisk' {
         PropertyEqualOrAny -InputObject (Get-ClusterResourceList -InputObject $Cluster -ResourceType $RES_PD) -Property ID -Value $Id
     }
     'ClusterResourceNetworkName' {
         PropertyEqualOrAny -InputObject (Get-ClusterResourceList -InputObject $Cluster -ResourceType $RES_NN) -Property ID -Value $Id
     }
     'ClusterResourceIPAddress' {
         $IPAddresses = PropertyEqualOrAny -InputObject (Get-ClusterResourceList -InputObject $Cluster -ResourceType $RES_IA) -Property ID -Value $Id
         ForEach ($IPAddress in $IPAddresses) {
            If ($Null -Eq $IPAddress) { Continue; }
            Add-Member -InputObject $IPAddress -MemberType NoteProperty -Name "Address" -Value (Get-ClusterParameter -InputObject $IPAddress -Name 'Address').Value;
            $IPAddresses
         }
     }
     'ClusterResourceVirtualMachineConfiguration' {
         PropertyEqualOrAny -InputObject (Get-ClusterResourceList -InputObject $Cluster -ResourceType $RES_VMC) -Property ID -Value $Id
     }
     'ClusterAvailableDisk' { 
         PropertyEqualOrAny -InputObject (Get-ClusterAvailableDisk -InputObject $Cluster) -Property ID -Value $Id
     }
     'ClusterSharedVolume' {
         $CSVs = PropertyEqualOrAny -InputObject (Get-ClusterSharedVolume -InputObject $Cluster) -Property ID -Value $Id
         ForEach ($CSV in $CSVs) {  
            If ($Null -Eq $CSV) { Continue; }
            Add-Member -InputObject $CSV -MemberType NoteProperty -Name "Cluster" -Value $Cluster.Name;
            Add-Member -InputObject $CSV -MemberType NoteProperty -Name "FriendlyVolumeName" -Value ($($CSV.SharedVolumeInfo).FriendlyVolumeName);
            Add-Member -InputObject $CSV -MemberType NoteProperty -Name "FileSystem" -Value ($($CSV.SharedVolumeInfo.Partition).FileSystem);
            If (($OSVersion -As [OSVersion]) -Ge [OSVersion]::v63) {
               $CSVState = Get-ClusterSharedVolumeState -InputObject $CSV;
               Add-Member -InputObject $CSV -MemberType NoteProperty -Name "StateInfo" -Value $CSVState.StateInfo;
               Add-Member -InputObject $CSV -MemberType NoteProperty -Name "FileSystemRedirectedIOReason" -Value $CSVState.FileSystemRedirectedIOReason;
               Add-Member -InputObject $CSV -MemberType NoteProperty -Name "BlockRedirectedIOReason" -Value $CSVState.BlockRedirectedIOReason;
            }
            $CSV
         }
     }
     'ClusterQuorum' {
         PropertyEqualOrAny -InputObject (Get-ClusterQuorum -InputObject $Cluster) -Property ID -Value $Id
     }

   } # switch ($Object)
});

#$Objects | fl *
#exit

Write-Verbose "$(Get-Date) Analyzing key";
$Objects = $( 
   Switch ($Keys[0]) {
      'VirtualMachine' {
         Write-Verbose "$(Get-Date) 'VirtualMachine.*' key detected";
#         $VMs = Get-ClusterResourceList -InputObject $Objects | ? { $RES_VM -eq $_.ResourceType }
         $VMs = Get-ClusterResourceList -InputObject $Objects -ResourceType $RES_VM 
         Switch ($Keys[1]) {
            'SummaryInformation' { 
               Get-MsvmSummaryInformation -InputObject $VMs -ResourceType $RES_VM; 
               # SummaryInformation property is expanded by Get-MsvmSummaryInformation
               # Get-Metric must be skip its
               $Keys[1] = ''; 
            }
            'Online'             { $VMs | ? {'online'         -eq $_.State }}
            'Offline'            { $VMs | ? {'offline'        -eq $_.State }}
            'OnlinePending'      { $VMs | ? {'onlinepending'  -eq $_.State }}
            'OfflinePending'     { $VMs | ? {'offlinepending' -eq $_.State }}
         }
         $Keys[0] = '';
      }
      'GenericService' {
         Write-Verbose "$(Get-Date) 'GenericService.*' key detected";
         $GSs = Get-ClusterResourceList -InputObject $Objects -ResourceType $RES_GS 
         Switch ($Keys[1]) {
            'Online'             { $GSs | ? { 'online'         -eq $_.State }}
            'Offline'            { $GSs | ? { 'offline'        -eq $_.State }}
         }
      $Keys[0] = '';
      }
      'ClusterParameter' {
         Write-Verbose "$(Get-Date) 'ClusterParameter.*' key detected";
         # Just fetch propertys from ClusterParameter table and add its to objects or return list if $Key == 'ClusterParameter'
         ForEach ($Object in $Objects) {
            If ($Null -Eq $Object) { Continue; }
            If ($Keys[1]) {
               $ClusterParameterValue = (Get-ClusterParameter -InputObject $Object -Name $Keys[1]).Value;
               # Need to use prefix to make unique property?
               # $Keys[1] = "__$($Keys[1])"
               Add-Member -InputObject $Object -MemberType NoteProperty -Name $Keys[1] -Value $ClusterParameterValue;
               $Object;
            } else {
               Get-ClusterParameter -InputObject $Object;
            }
         }
      $Keys[0] = '';
      }
      # No virtual keys defined -> $Objects must be saved for future processing 
      Default { $Objects; } 
   }
);
switch ($Action) {
   'Discovery'   {
       Switch ($ObjectType) {
          'Cluster'                       { $ObjectProperties = @("ID", "NAME"); }
          'ClusterNode'                   { $ObjectProperties = @("ID", "CLUSTER", "NAME", "STATE"); }
          'ClusterNetwork'  	          { $ObjectProperties = @("ID", "CLUSTER", "NAME", "STATE", "ROLE"); }
          'ClusterNetworkInterface'       { $ObjectProperties = @("ID", "CLUSTER", "NODE", "NAME", "STATE", "NETWORK", "NETWORKADDRESS", "ADDRESS"); }
          'ClusterResourceDHCPService'    { $ObjectProperties = @("ID", "CLUSTER", "OWNERGROUP", "OWNERNODE", "NAME", "STATE"); }
          'ClusterResourceGenericService' { $ObjectProperties = @("ID", "CLUSTER", "OWNERGROUP", "OWNERNODE", "NAME", "STATE"); }
          'ClusterResourceVirtualMachine' { $ObjectProperties = @("ID", "CLUSTER", "OWNERGROUP", "OWNERNODE", "NAME", "STATE"); }
          'ClusterResourcePhysicalDisk'   { $ObjectProperties = @("ID", "CLUSTER", "OWNERGROUP", "OWNERNODE", "NAME", "STATE"); }
          'ClusterResourceNetworkName'    { $ObjectProperties = @("ID", "CLUSTER", "OWNERGROUP", "OWNERNODE", "NAME", "STATE"); }
          'ClusterResourceIPAddress'      { $ObjectProperties = @("ID", "CLUSTER", "OWNERGROUP", "OWNERNODE", "NAME", "STATE", "ADDRESS"); }
          'ClusterResourceVirtualMachineConfiguration' { $ObjectProperties = @("ID", "CLUSTER", "OWNERGROUP", "OWNERNODE", "NAME", "STATE"); }
          'ClusterAvailableDisk'          { $ObjectProperties = @("ID", "CLUSTER", "NAME", "STATE", "ROLE"); }
          'ClusterSharedVolume'           { $ObjectProperties = @("ID", "CLUSTER", "NAME", "STATE", "FRIENDLYVOLUMENAME", "FILESYSTEM"); }
       }  
       Write-Verbose "$(Get-Date) Generating LLD JSON";
       $Result =  Make-JSON -InputObject $Objects -ObjectProperties $ObjectProperties -Pretty;
   }
   # Get metrics or metric list
   'Get' {
      If ($Null -Eq $Objects) {
         Exit-WithMessage -Message "No objects in collection" -ErrorCode $ErrorCode;
      }
     Write-Verbose "$(Get-Date) Getting metric related to key: '$Key'";
     $Result = PrepareTo-Zabbix -InputObject (Get-Metric -InputObject $Objects -Keys $Keys) -ErrorCode $ErrorCode;
   }
   # Get-Metric can return an array of objects. In this case need to take each item and add its to $r
   'Sum' {
      Write-Verbose "$(Get-Date) Sum objects";  
      $Result = $( 
         If ($Objects) { 
            $Result = 0;
            ForEach ($Object in $Objects) {
               $Result += Get-Metric -InputObject $Object -Keys $Keys;
            }
            $Result
         } Else { 0 } 
      ); 
   }
   # Count selected objects
   'Count' { 
       Write-Verbose "$(Get-Date) Counting objects";  
       # if result not null, False or 0 - return .Count
       $Result = $(if ($Objects) { @($Objects).Count } else { 0 } ); 
   }
}  

# Convert string to UTF-8 if need (For Zabbix LLD-JSON with Cyrillic chars for example)
if ($consoleCP) { 
   Write-Verbose "$(Get-Date) Converting output data to UTF-8";
   $Result = $Result | ConvertTo-Encoding -From $consoleCP -To UTF-8; 
}

# Break lines on console output fix - buffer format to 255 chars width lines 
if (!$defaultConsoleWidth) { 
   Write-Verbose "$(Get-Date) Changing console width to $CONSOLE_WIDTH";
   mode con cols=$CONSOLE_WIDTH; 
}

Write-Verbose "$(Get-Date) Finishing";

$Result;
