ps_vsphere_statsadv
===================

This module performs performance collections in a similar way to the native PowerCLI cmdlets but leveraging the Vim interface directly.  This allows you to collect on objects that are not allowed through PowerCLI and get advanced control of the type of collections being performed.<br>
<br>
See the module for examples of the cmdlets.<br>
<br>
Connect-VIServerVIM<br>
ConvertTo-StatsAdvConsolidatedRow<br>
Get-PerfCounter<br>
Get-StatAdv<br>
Get-StatCompositeAdv<br>
Get-StatRealtime<br>
Get-StatRollup<br>
Get-StatTypeAdv<br>
<br>
<br>
Example<br>
===================
Load PowerCLI<br>
<br>
$cred = get-credential<br>
Connect-VIServer -server vc -credential $cred<br>
Connect-VIServerVIM -server vc -credential $cred<br>
<br>
Get-VM -name test | Get-StatAdv -maxSamples 100 -Interval 86400<br>
