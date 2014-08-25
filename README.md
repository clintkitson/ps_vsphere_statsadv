ps_vsphere_statsadv
===================

This module performs performance collections in a similar way to the native PowerCLI cmdlets but leveraging the Vim interface directly.  This allows you to collect on objects that are not allowed through PowerCLI and get advanced control of the type of collections being performed.

See the module for examples of the cmdlets.

Connect-VIServerVIM
ConvertTo-StatsAdvConsolidatedRow
Get-PerfCounter
Get-StatAdv
Get-StatCompositeAdv
Get-StatRealtime
Get-StatRollup
Get-StatTypeAdv


Example
===================
Load PowerCLI

$cred = get-credential
Connect-VIServer -server vc -credential $cred
Connect-VIServerVIM -server vc -credential $cred

Get-VM -name test | Get-StatAdv -maxSamples 100 -Interval 86400
