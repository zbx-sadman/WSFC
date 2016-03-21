## WSFC Miner 
This is a little Powershell script help to fetch metric's values from Windows Server Failover Cluster (WSFC).

Actual release 1.0.0

Tested on Windows Server 2008 R2 SP1, Powershell 2.0


Supported objects:

- _Cluster_ - Windows Server Failover Cluster (WSFC);
- _ClusterNode_ - WSFC node;
- _ClusterNetwork_ - WSFC Network;
- _ClusterNetworkInterface_ - failover cluster's network adapter;
- _ClusterAvailableDisk_ - WSFC Available (unused) Disk resources. That disk can support Failover Clustering and are visible to all nodes, but are not yet part of the set of clustered disks.;
- _ClusterResourceGenericService_ - WSFC resource 'Generic Service';
- _ClusterResourceVirtualMachine_ - WSFC resource 'Virtual Machine';
- _ClusterResourceVirtualMachineConfiguration_ - WSFC resource 'Virtual Machine Configuration';
- _ClusterResourceIPAddress_ - WSFC resource 'IP Address';
- _ClusterResourceNetworkName_ - WSFC resource 'Network Name';
- _ClusterResourcePhysicalDisk_ - WSFC resource 'Physical Disk';
- _ClusterSharedVolume_ - WSFC Shared Volumes;
- _ClusterQuorum_ - WSFC cluster's quorum.

Virtual keys for 'Cluster', 'ClusterNode' objects:
- _VirtualMachine.Online_ - failover cluster's resource 'Virtual Machine' in Online state;
- _VirtualMachine.Offline_ - ... in Offline state;
- _VirtualMachine.OnlinePending_ - ... in OnlinePending state;
- _VirtualMachine.OfflinePending_ - ... in OfflinePending state;
- _VirtualMachine.SummaryInformation_ - set of metrics related to cluster resource 'Virtual Machine' and fetched from MsVM_virtualSystemManagementService class with WMI-query
- _GenericService.Online_  - failover cluster's resource 'Generic Service' in Online state;
- _GenericService.Offline_ - ... in Offline state;

Virtual keys for all object which contains in ClusterParameter (see Get-ClusterParameter cndlet) table
- _ClusterParameter.\<metric\>_ - object's metric from ClusterParameter table.


Actions
- _Discovery_ - Make Zabbix's LLD JSON;
- _Get_       - Get metric from collection item;
- _Sum_       - Sum metrics of collection items;
- _Count_     - Count collection items.


###How to use standalone

    # Get Cluster name
    powershell -NoProfile -ExecutionPolicy "RemoteSigned" -File "wsfc.ps1" -Action "Get" -ObjectType "Cluster" -Key "Name" -Id "f4479814-35d4-41c5-babd-c0697769ac31"

    # Get PercentFree metric value from SharedVolumeInfo.Partition table for volume with ID=b8b67dbf-e66f-443e-926e-be1d1621ece5
    ..."wsfc.ps1" -Action "Get" -ObjectType "ClusterSharedVolume" -Key "SharedVolumeInfo.Partition.PercentFree" -Id "b8b67dbf-e66f-443e-926e-be1d1621ece5"

    # Get total number of vCPUs assigned to all clustered VMs which hosted on Node with ID=00000000-0000-0000-0000-000000000001
    ... "wsfc.ps1" -Action "Sum" -ObjectType "ClusterNode" -Key "SummaryInformation.VirtualMachine.NumberOfProcessors" -Id "00000000-0000-0000-0000-000000000001"

    # Get total number of Memory assigned (dynamically for WS2008 R2 SP1+) to all clustered VMs which placed in Cluster with ID=f4479814-35d4-41c5-babd-c0697769ac31
    ... "wsfc.ps1" -Action "Sum" -ObjectType "Cluster" -Key "SummaryInformation.VirtualMachine.NumberOfProcessors" -Id "00000000-0000-0000-0000-000000000001"

    # Get formatted list of 'ClusterSharedVolume' object metrics accessed with property 'SharedVolumeInfo.Partition'. Verbose messages is enabled. 
    ... "wsfc.ps1" -Action "Get" -ObjectType "ClusterSharedVolume" -Key "SharedVolumeInfo.Partition" -ID "8e8fb118-2601-4a06-ab9a-f0a1260bd247" -DefaultConsoleWidth -Verbose



###How to use with Zabbix
1. Make unsigned .ps1 scripts executable at all time with _powershell.exe -command "Set-ExecutionPolicy RemoteSigned"_ or at once with _-ExecutionPolicy_ command line option;
2. If you still use non-clustered Zabbix Agent on any clusternode - be sure that its ListenIP not 0.0.0.0. Otherwise you can sometime get error 1067 while migrate clustered Zabbix Agent due its IP may be already used by local Zabbix Agent;
3. Create copy of Zabbix Agent config for using with clustered Zabbix Agent (_zabbix\_agentd\_WSFC-A.conf_ for example); 
4. Set Zabbix Agent's / Server's _Timeout_ to more that 3 sec (may be 10 or 30);
5. Add to _zabbix\_agentd\_WSFC-A.conf_ this string: _UserParameter=wsfc[*], powershell -NoProfile -ExecutionPolicy "RemoteSigned" -File C:\zabbix\scripts\wsfc.ps1 -Action "$1" -Object "$2" -Key "$3" -Id "$4" -ErrorCode $5_ ;
6. Use with _zabbix\_agentd\_WSFC-A.conf_ params: _Hostname=wsfc-a.mynet.local_ and _ListenIP=192.168.0.69_, where FDQN-hostname is name what you want use as host-record on Zabbix Server and IP-address is address that you plan to use on step 10;
7. Put _wsfc.ps1_ to _C:\zabbix\scripts_ dir and _zabbix\_agentd\_WSFC-A.conf_ to _C:\zabbix_ dir on all cluster nodes. Also you can use Windows Share if you want; 
8. Create new (double) Zabbix service on every node with command: _zabbix_agentd.exe -c c:\zabbix\zabbix\_agentd\_WSFC-A.conf -i **-m**_. Do not start new service - its will auto-started by WSFC on service's Owner node;
9. If you need to use _*.SummaryInformation.*_ metrics, that you must change Clustered Zabbix service account from "Local System" to any account, that have local admin rights to use FailoverClusters Cmdlet's and have rights to make WMI-queries to all cluster nodes over network. Otherwise you will got script error;
10. Create new "Generic Service" for your cluster with Failover Cluster MMC, assign to its an IP-address from step 6 and start its;
11. Import [template](https://github.com/zbx-sadman/WSFC/tree/master/Zabbix_Templates) to Zabbix Server;
12. Create new "WSFC-A Cluster" (or "MyCluster" for example) host on Zabbix server. Its must have hostname and IP-address from step 6;
13. Think twice before link Template to host and disable discovery rules that not so important (may be "Virtual Machines", "Generic Services", "Cluster Networks"). Otherwise u can get over 9000% CPU load with PowerShell calls;
14. Pray and link template;
15. Enjoy.

**Note**
Do not try import Zabbix v2.4 template to Zabbix _pre_ v2.4. You need to edit .xml file and make some changes at discovery_rule - filter tags area and change _#_ to _<>_ in trigger expressions. I will try to make template to old Zabbix.

**Note**
In template used Item's type _Zabbix Agent (active)_. You must set up _ServerActive_ directive of Zabbix Agent or change Item's type to _Zabbix Agent_. In this case number of pollers of Zabbix Server must be increased, because any run of PowerShell script will freeze poller thread to 2 sec (on my hardware).

###Hints
- To see keys, run script without "-Key" option: _powershell -NoProfile -ExecutionPolicy "RemoteSigned" -File C:\zabbix\scripts\wsfc.ps1 -Action "Get" -Object "**Object**"_ \[-Key "{SummaryInformation.VirtualMachine | ClusterParameter}"\]. Note that not all objects have related metrics in ClusterParameter & SummaryInformation tables (try use this keys with 'ClusterResourceVirtualMachine' object for test). You can refer to MSDN ;)
- Please read descrition to Discovery Rules and Items to find helpful info (links to MSDN pages, that describe metrics);
- If you use non-english (for example Russian Cyrillic) symbols in VM's names and want to get correct UTF-8 on Zabbix Server side, then you must add _-consoleCP **your_native_codepage**_ parameter to command line. For example to convert from Russian Cyrillic codepage (CP866), use _powershell -File C:\zabbix\scripts\wsfc.ps1 -Action "$1" -Object "$2" -Key "$3" -Id "$4" -ErrorCode "$5" -consoleCP CP866_;
- To leave console default width while run script use _-defaultConsoleWidth_ option.
- If you get Zabbix's "Should be JSON" - try to increase cols in _mode con cols=255_ command inside _wsfc.ps1_. Powershell use console width to format output JSON-lines and can break its. 

Beware: frequent requests to PowerShell script eat CPU and increase Load. To avoid it - don't use small update intervals with Zabbix's Data Items and disable unused.
