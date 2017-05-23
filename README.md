## WSFC Miner 
This is a little Powershell script help to fetch metric's values from Windows Server Failover Cluster (WSFC).

Actual release 1.2.2

Tested on:
- Production mode: Windows Server 2008 R2 SP1, Powershell 2;
- Non-production mode: Windows Server 2012 R2, Powershell 4.
 
Supported objects:

- _Cluster_ - Windows Server Failover Cluster (WSFC);
- _ClusterNode_ - WSFC node;
- _ClusterNetwork_ - WSFC Network;
- _ClusterNetworkInterface_ - failover cluster's network adapter;
- _ClusterAvailableDisk_ - WSFC Available (unused) Disk resources. That disk can support Failover Clustering and are visible to all nodes, but are not yet part of the set of clustered disks.;
- _ClusterResourceDHCPService_ - WSFC resource 'DHCP Service';
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


### How to use standalone

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



### How to use with Zabbix
I recommend start use WSFC Miner as non-clustered service, tune it with Zabbix and make its clustered then.

####Use as non-clustered Service
1. Include [zbx_wsfc.conf](https://github.com/zbx-sadman/WSFC/tree/master/Zabbix_Templates/zbx_wsfc.conf) to Zabbix Agent config on any cluster node;
2. Put _wsfc.ps1_ to _C:\zabbix\scripts_ dir. If you want to place script to other directory, you must edit _zbx\_wsfc.conf_ to properly set script's path; 
3. Set Zabbix Agent's / Server's _Timeout_ to more that 3 sec (may be 10 or 30);
4. If you need to use _*.SummaryInformation.*_ metrics - you must change Zabbix Service account from "Local System" to any account, 
   that have local admin rights to use FailoverClusters Cmdlet's and have rights to make WMI-queries to all cluster nodes over network. 
   Otherwise you will got script error;
5. Import [template](https://github.com/zbx-sadman/WSFC/tree/master/Zabbix_Templates) to Zabbix Server;
6. Think twice before link Template to host and disable discovery rules that not so important (may be "Virtual Machines", "Generic Services", 
   "Cluster Networks"). Otherwise u can get over 9000% CPU load with PowerShell calls;
7. Pray and link template;
8. Enjoy.

#### Use as failover Generic Service
1. If you want use local (non-clustered) and failover (clustered) Zabbix Agent at the same time - you must to change Zabbix Agent's directive ListenPort in "clustered agent" config from default to another unused (may be 16092 or so). Otherwise you can sometime get error 1067 when clustered Zabbix Agent will migrate. This is due first started instance of Agent bind to all available host's addresses and second instance just exit when started;
2. Create copy of Zabbix Agent config (call it _zabbix\_agentd\_WSFC-A.conf_ for example) on the one cluster node; 
3. Include [zbx_wsfc.conf](https://github.com/zbx-sadman/WSFC/tree/master/Zabbix_Templates/zbx_wsfc.conf) to Zabbix Agent config, if you have not done this before;
4. Choose new IP-address and domain name for using with Generic Service. It's should not be Cluster's IP and Hostname. 
   Change ListenIP & Hostname directive to new values in _zabbix\_agentd\_WSFC-A.conf_;
5. Put _wsfc.ps1_ and _zabbix\_agentd\_WSFC-A.conf_ to every node in cluster (or try to use Windows Shares); 
6. On every node deinstall service of local Zabbix Agent and install it again with **-m** key 
   (zabbix_agentd.exe -c ... -x, zabbix_agentd.exe -c ... -d, zabbix_agentd.exe -c ... -i -m, zabbix_agentd.exe -c ... -s -m);
7. On every node install second Zabbix Agent's service with _zabbix\_agentd\_WSFC-A.conf_ and **-m** key 
   (zabbix_agentd.exe -c ..._zabbix\_agentd\_WSFC-A.conf_ -i -m). Don't start that service manually - its will auto-started by WSFC on service's Owner node;
8. If you need to use _*.SummaryInformation.*_ metrics - you must change Zabbix Service account from "Local System" to any account, 
   that have local admin rights to use FailoverClusters Cmdlet's and have rights to make WMI-queries to all cluster nodes over network.
   Otherwise you will got script error;
9. Create new "Generic Service" for your cluster with Failover Cluster MMC, assign to its an IP-address and hostname, which was defined on step 4;
10. Import [template](https://github.com/zbx-sadman/WSFC/tree/master/Zabbix_Templates) to Zabbix Server;
11. Think twice before link Template to host and disable discovery rules that not so important (may be "Virtual Machines", "Generic Services", 
   "Cluster Networks"). Otherwise u can get over 9000% CPU load with PowerShell calls;
12. On Zabbix server create new host with IP-address and hostname from step 4;
13. Pray and link template;
14. Start Generic Service, that you create on step 9 with with Failover Cluster MMC;
15. Enjoy. May be.

**Note**
Do not try import Zabbix v2.4 template to Zabbix _pre_ v2.4. You need to edit .xml file and make some changes at discovery_rule - filter tags area and change _#_ to _<>_ in trigger expressions. I will try to make template to old Zabbix.

**Note**
In template used Item's type _Zabbix Agent (active)_. You must set up _ServerActive_ directive of Zabbix Agent or change Item's type to _Zabbix Agent_. In this case number of pollers of Zabbix Server must be increased, because any run of PowerShell script will freeze poller thread to 2 sec (on my hardware).

### Hints
- To see keys, run script without **-Key** option: 
  _... "wsfc.ps1" -Action "Get" -Object "**Object**"_ \[-Key "{SummaryInformation.VirtualMachine | ClusterParameter}"\]. 
  Note that not all objects have related metrics in ClusterParameter & SummaryInformation tables (try use this keys with 'ClusterResourceVirtualMachine' object for test). 
  You can refer to MSDN for information;)
- Please read descrition to Discovery Rules and Items to find helpful info (links to MSDN pages, that describe metrics);
- If you use non-english (for example Russian Cyrillic) symbols in VM's names and want to get correct UTF-8 on Zabbix Server side, 
  then you must add _-consoleCP **your_native_codepage**_ parameter to command line. For example to convert from Russian Cyrillic codepage (CP866), 
  use _... "wsfc.ps1" ... -consoleCP CP866_
- For debug in standalone mode use _-defaultConsoleWidth_ option to leave console default width while run script and
   _-Verbose_ to get additional processing information;
- If you get Zabbix's "Should be JSON" - try to increase the number value in CONSOLE_WIDTH constant variable inside _wsfc.ps1_. 
  Powershell use console width to format output JSON-lines and can break its. 
- With ClusterNetworkInterface discovery you can use {#NETWORKADDRESS} to filter non-routables networks for exclude non-pingable IP addresses to avoid 
  switching related items to unsupported state.

**Beware** frequent requests to PowerShell script eat CPU and increase Load. To avoid it - don't use small update intervals with Zabbix's Data Items and disable unused.
