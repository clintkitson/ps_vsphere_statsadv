##
#
# vElemental
# @clintonskitson
#
# ps_vsphere_statsadv.psm1 - A reproduction of PowerCLI Get-Stat functionality using vSphere SDK SOAP methods
#
##

#http://pubs.vmware.com/vsphere-51/index.jsp?topic=%2Fcom.vmware.wssdk.pg.doc%2FPG_Performance.18.4.html


#ConvertTo-StatsAdvConsolidatedRow (get-vm bsg05200 | get-statadv -Interval 20 -maxsamples 180 -Start ($global:DefaultVIServer.ExtensionData.CurrentTime().ToLocalTime()).AddMinutes(-120)) | export-csv -notypeinformation vm.csv
#ConvertTo-StatsAdvConsolidatedRow (get-datacenter | get-statadv -Interval 300 -Start ($global:DefaultVIServer.ExtensionData.CurrentTime().ToLocalTime()).AddMinutes(-10)) | export-csv -notypeinformation datacenter.csv
#ConvertTo-StatsAdvConsolidatedRow (get-datastore vnx5700-02-nfs-07 | get-statadv -Interval 300 -Start ($global:DefaultVIServer.ExtensionData.CurrentTime().ToLocalTime()).AddMinutes(-10)) | export-csv -notypeinformation datastore.csv
#ConvertTo-StatsAdvConsolidatedRow (get-vmhost bsg05035.lss.emc.com | get-statadv -Interval 20 -maxsamples 180 -Start ($global:DefaultVIServer.ExtensionData.CurrentTime().ToLocalTime()).AddMinutes(-10)) | export-csv -notypeinformation vmhost.csv


function ConvertTo-StatsAdvConsolidatedRow {
    [CmdletBinding()]
    param(
        [PSObject[]]$statsAdv
    )
    End {
	[array]$arrMetricId = $statsAdv | %{ "$($_.metricId) $($_.unit) $($_.instance)" } | select -unique | sort
	$statsAdv | group entity,timestamp | %{
	    $result = $_.group
	    $hashresults=[ordered]@{entity=$result[0].entity;timestamp=$result[0].timestamp}
	    $result | %{ $hashresults.("$($_.metricId) $($_.unit) $($_.instance)".ToLower()) = $_.value }
	    new-object -type psobject -property $hashresults
	} | sort timestamp,entity | select -property (("timestamp","entity",$arrMetricId) | %{$_})

    } 
}

#$results = get-vm -name bsg05* | Get-vCOpsResourceMetric -metricKey (gc .\proxy_metrics.txt) -startDate (Get-Date).AddMinutes(-20)

#$results | group name,date | %{ 
#$result=$_.group;
#$hashresults=@{VM=$result[0].name;date=$result[0].date};
#$result | sort metrickey | %{ $hashresults.($hashAttributes.($_.metrickey)) = $_.value };
#new-object -type psobject -property $hashresults
#} | sort date,vm | export-csv test.csv -notypeinformation





#Connect-VIServerVIM -username root -password pass -viserver vcip
#Connect-VIServerVIM -credential (get-credential) -viserver vcip
function Connect-VIServerVIM {
    [CmdletBinding()]
    param(
        [string]$Username,
        [string]$Password,
        [PsCredential]$Credential,
        [Int]$ServiceTimeout=100000,
        $Server=$(throw "need -Server")
    )
    
    function Decrypt-SecureString {
        param(
            [Parameter(ValueFromPipeline=$true,Mandatory=$true,Position=0)]
            [System.Security.SecureString]
            $sstr
        )
        $marshal = [System.Runtime.InteropServices.Marshal]
        $ptr = $marshal::SecureStringToBSTR( $sstr )
        $str = $marshal::PtrToStringBSTR( $ptr )
        $marshal::ZeroFreeBSTR( $ptr )
        $str
    }

    function Get-ServiceInstance {
        (New-Object "Vim.ManagedObjectReference" -property @{type="ServiceInstance";Value="ServiceInstance"})
    }

    @("vmware.vimautomation.core") | %{
          if(!(get-pssnapin $_ -ea 0)) {
            try { 
                add-pssnapin $_ -ea stop| out-null
            } catch {
                throw "Could not load PowerCLI snapin"
            }
          }
    }


    if((!$username -or !$password) -and !$credential) {
        Throw "Missing eitheer -username, -password OR -credential"
    }

    if($Credential) {
        $Username = $Credential.UserName
        $Password = Decrypt-SecureString $Credential.Password
    }
    $global:vimClient = New-Object Vmware.Vim.VimClient

    [void]$global:vimClient.Connect("https://$Server/sdk")
    $global:vimClient.login($username,$password)
    $global:vimClient.ServiceTimeout = $ServiceTimeout

    $vimVersion = $global:vimClient.version.toString().Replace('Vim','')

    [System.Type]$typeAcceleratorsType = [System.Management.Automation.PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators', $true, $true)
    $VimAssembly = ([appdomain]::currentdomain.GetAssemblies() | where {$_.ManifestModule.ToString() -eq "VimService$($VimVersion).dll"})

    $VimAssembly.GetExportedTypes() | %{
        $typeAcceleratorsType::Add("Vim.$(($_.FullName -split "\.",2)[-1])",$_)
    }

    $global:vimServiceContent = $global:vimClient.VimService.RetrieveServiceContent((Get-ServiceInstance))
}

#Get-VM name | Get-StatRealtime
#Get-VM name | Get-StatRealtime -MaxSamples 2
Function Get-StatRealtime {
[CmdletBinding()]
    Param (
        [Parameter(Mandatory=$True, Position=1, ValueFromPipeline=$true)]
        [PSObject]$Entity,
        $MaxSamples=1
    )
    Process {
        $Entity | %{ $_ | Get-Stat -Realtime -MaxSamples $MaxSamples -Stat ($_ | Get-StatType -Realtime) } | sort MetricId,Instance,Timestamp  | select Timestamp,Entity,Instance,MetricId,Value,Unit
    }
}


Function Get-StatRollup {
[CmdletBinding()]
    Param (
        [Parameter(Mandatory=$True, Position=1, ValueFromPipeline=$true)]
        [PSObject]$Entity,
        [Datetime]$Start,
        [Datetime]$Finish,
        [Int32]$Interval=7200
    )
    Process {
        $Entity | %{ $_ | Get-Stat -Interval $Interval -Stat ($_ | Get-StatType -Interval $Interval) } | sort MetricId,Instance,Timestamp  | select Timestamp,Entity,Instance,MetricId,Value,Unit
    }
}


Function Get-PerfCounter {
[CmdletBinding()]
    Param()
    [Vim.ObjectSpec[]]$os = New-Object Vim.ObjectSpec -property @{obj=$vimServiceContent.perfManager;skip=$false}
    [Vim.PropertySpec[]]$ps = New-Object Vim.PropertySpec -property @{type="PerformanceManager";pathSet="perfCounter"}
    [Vim.PropertyFilterSpec[]]$pfs = New-Object Vim.PropertyFilterSpec -property @{propSet=$ps;objectSet=$os}
    $global:vimClient.VimService.RetrieveProperties($global:vimServiceContent.PropertyCollector,$pfs).PropSet.Val
}



#Get-VM -name test | Get-StatAdv -maxSamples 100 -Interval 86400
#Get-VM -name test | Get-StatAdv -Interval 300 -Start ((Get-Date).AddHours(-10))
#Get-View -viewtype virtualmachine | select -first 1
#(get-vmhost)[-1] | get-statadv -realtime -maxsamples 1 -filterStat {$_ -match "^mem"}
#(get-vmhost)[-1] | get-statadv -realtime -maxsamples 1 | group instance
#get-view -ViewType "folder" | select -first 1 | get-statadv -Interval 300
Function Get-StatAdv {
[CmdletBinding()]
    Param (
        [Parameter(Mandatory=$True, Position=1, ValueFromPipeline=$true)]
        [PSObject[]]$Entity,
        [String[]]$Stat,
        [Datetime]$Start,
        [Datetime]$Finish,
        [Int32]$MaxSamples="100",
        [Int32]$IntervalMins,
        [Int32]$Interval=86400,
        [String[]]$Instance="*",
        [Switch]$Realtime,
        [String]$Server,
        [ScriptBlock]$filterStat,
        [Switch]$OutRawAPI
    )
    Begin {
        $arrObjects = @()
        [int]$IntervalId = if($Realtime) { 20 } elseif ($IntervalMins) { $IntervalMins * 60 } elseif($Interval) { $Interval }
        $timeDiff = (($global:DefaultVIServer.ExtensionData.CurrentTime().ToLocalTime()) - (Get-Date)).TotalSeconds
        if($Start) { $Start = $Start.AddSeconds($timeDiff) }
        if($Finish) { $Finish = $Finish.AddSeconds($timeDiff) }
    }
    Process {
        $Moref = if($Entity.Moref) { $Entity.Moref } else { $Entity.ExtensionData.Moref }
        $arrObjects += New-Object -type PsObject -Property @{"Entity"=$Entity;"Moref"=$Moref}
    }
    End {
        $hashEntityLookup = @{}
        $arrObjects | %{ $hashEntityLookup.($_.Moref.Value) = $_ }

        [Vim.PerfCounterInfo[]]$PerfCounterInfo = Get-PerfCounter

        $hashCounterLookup = @{}
        $hashCounterLookupReverse = @{}
        $PerfCounterInfo | Select @{n="FullCounterName";e={"$($_.GroupInfo.key).$($_.NameInfo.key).$($_.rollupType)"}},@{n="counterId";e={$_.Key}},UnitInfo | %{
            $hashCounterLookup.($_.FullCounterName) = $_.counterId
            $hashCounterLookupReverse.($_.counterId) = $_
        }

        if($filterStat) { 
            $Stat = $arrObjects[0].Entity | Get-StatTypeAdv -Interval $IntervalId | where -filterScript $filterStat
        }

        [Vim.PerfMetricId[]]$perfMetricIds = for($i=0;$i -lt $stat.count;$i++) {
            $counterName = $stat[$i]
            $metricId = New-Object Vim.PerfMetricId
            $metricId.counterId = $hashCounterLookup.$counterName
            $metricId.instance = $Instance
            $metricId
        }

        [Vim.PerfQuerySpec[]]$pgsList = %{
            $arrObjects | %{
                $querySpecification = New-Object Vim.perfQuerySpec
                $querySpecification.Entity = New-Object Vim.ManagedObjectReference -property @{type=$_.Moref.Type;value=$_.Moref.Value}
                
                $querySpecification.IntervalId = $intervalId 
                $querySpecification.IntervalIdSpecified = $True
                $querySpecification.Format = "normal"
                $querySpecification.MetricId = $perfMetricIds
                if($maxSamples) {
                    $querySpecification.maxSample = $maxSamples 
                    $querySpecification.maxSampleSpecified = $True
                }
                if($start) { 
                    $querySpecification.startTime = $start
                    $querySpecification.startTimeSpecified = $True
                }
                if($finish) {
                    $querySpecification.endTime = $finish
                    $querySpecification.endTimeSpecified = $True
                }
                $querySpecification
            }
        }
write-verbose ($pgslist | out-string)

        $QueryPerfResults = $global:vimClient.VimService.QueryPerf($vimServiceContent.perfManager,$pgsList)

        if($OutRawAPI) {
            Return ($QueryPerfResults)
        }

        $QueryPerfResults | where {$_.sampleInfo} | %{
            $retrievedStat = $_
            [array]$arrSampleInfo = $retrievedStat.sampleInfo
            $retrievedStat.Value | %{
                $retrievedStatInstance = $_
                $Unit = $hashCounterLookupReverse.($retrievedStatInstance.id.counterId).unitInfo.label
                for($i=0;$i -lt $arrSampleInfo.count;$i++) {
                    $retrievedStatInstance.Value[$i] | Select @{n="MetricId";e={$hashCounterLookupReverse.($retrievedStatInstance.id.counterId).FullCounterName}},
                                                      @{n="Timestamp";e={$arrSampleInfo[$i].Timestamp.ToLocalTime()}},
                                                      @{n="Entity";e={$hashEntityLookup.($retrievedStat.Entity.Value).Entity.Name}},
                                                      @{n="EntityId";e={"$($retrievedStat.Entity.Type)-$($retrievedStat.Entity.Value)"}},
                                                      @{n="IntervalSecs";e={$arrSampleInfo[$i].Interval}},
                                                      @{n="Unit";e={$Unit}},
                                                      @{n="Instance";e={$retrievedStatInstance.id.Instance}},
                                                      @{n="Value";e={ if($Unit -eq "Percent") { $_/100 } else { $_ }}}
                }
            }
        }
    }
}


function Get-StatTypeAdv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True, Position=1, ValueFromPipeline=$true)]
        [PSObject[]]$Entity,
        $Interval=20,
        $Level=4,
        [array]$RollupType
    )
    Begin {
        $arrObjects = @()
    }
    Process {
        $Moref = if($Entity.Moref) { $Entity.Moref } else { $Entity.ExtensionData.Moref }
        $arrObjects += New-Object -type PsObject -Property @{"Entity"=$Entity;"Moref"=$Moref}
    }
    End {

        [Vim.PerfCounterInfo[]]$PerfCounterInfo = Get-PerfCounter | where {$_.Level -le $Level -and (!$RollupType -or $RollupType -contains $_.RollupType)}

        $hashCounterLookup = @{}
        $hashCounterLookupReverse = @{}
        $PerfCounterInfo | Select *,@{n="MetricId";e={"$($_.GroupInfo.key).$($_.NameInfo.key).$($_.rollupType)"}},@{n="counterId";e={$_.Key}} | %{
            $hashCounterLookupReverse.($_.counterId) = $_
        }

        $startTime = Get-Date
        $startTimeSpecified = $False
        $endTime = Get-Date
        $endTimeSpecified = $False
        
        $arrObjects | %{
            $Moref = New-Object Vim.ManagedObjectReference -property @{type=$_.Moref.Type;value=$_.Moref.Value}
            $retrievedPerfMetrics =  $global:vimClient.VimService.QueryAvailablePerfMetric($vimServiceContent.perfManager,$Moref,$startTime,$startTimeSpecified,$endTime,$endTimeSpecified,$Interval,$True)
            $retrievedPerfMetrics | %{ $hashCounterLookupReverse.($_.counterid).MetricId } | Select -Unique
        }
    }
}


#(get-vmhost)[-1] | %{ $_ | get-statcompositeadv -stat "disk.maxTotalLatency.latest" -Interval 7200 -Start ((Get-date).addHours(-24))}  | ft *
Function Get-StatCompositeAdv {
[CmdletBinding()]
    Param (
        [Parameter(Mandatory=$True, Position=1, ValueFromPipeline=$true)]
        [PSObject[]]$Entity,
        [String[]]$Stat,
        [Datetime]$Start,
        [Datetime]$Finish,
        [Int32]$IntervalMins,
        [Int32]$Interval=86400,
        [String[]]$Instance="",
        [Switch]$Realtime,
        [String]$Server
    )
    Begin {
        $arrObjects = @()
        [int]$IntervalId = if($Realtime) { 20 } elseif ($IntervalMins) { $IntervalMins * 60 } elseif($Interval) { $Interval } 
        $timeDiff = (($global:DefaultVIServer.ExtensionData.CurrentTime().ToLocalTime()) - (Get-Date)).TotalSeconds
        if($Start) { $Start = $Start.AddSeconds($timeDiff) }
        if($Finish) { $Finish = $Finish.AddSeconds($timeDiff) }
    }
    Process {
        $Moref = if($Entity.Moref) { $Entity.Moref } else { $Entity.ExtensionData.Moref }
        $arrObjects += New-Object -type PsObject -Property @{"Entity"=$Entity;"Moref"=$Moref}
    }
    End {
        $hashEntityLookup = @{}
        $arrObjects | %{ $hashEntityLookup.($_.Moref.Value) = $_ }

        [Vim.PerfCounterInfo[]]$PerfCounterInfo = Get-PerfCounter

        $hashCounterLookup = @{}
        $hashCounterLookupReverse = @{}
        $PerfCounterInfo | Select @{n="FullCounterName";e={"$($_.GroupInfo.key).$($_.NameInfo.key).$($_.rollupType)"}},@{n="counterId";e={$_.Key}},UnitInfo | %{
            $hashCounterLookup.($_.FullCounterName) = $_.counterId
            $hashCounterLookupReverse.($_.counterId) = $_
        }

        if(!$Stat) { $Stat = $arrObjects[0].Entity | Get-StatTypeAdv }

        [Vim.PerfMetricId[]]$perfMetricIds = for($i=0;$i -lt $stat.count;$i++) {
            $counterName = $stat[$i]
            $metricId = New-Object Vim.PerfMetricId
            $metricId.counterId = $hashCounterLookup.$counterName
            $metricId.instance = $Instance
            $metricId
        }

        $arrObjects | %{
            [Vim.PerfQuerySpec]$pgsList = %{
                $querySpecification = New-Object Vim.perfQuerySpec
                $querySpecification.Entity = New-Object Vim.ManagedObjectReference -property @{type=$_.Moref.Type;value=$_.Moref.Value}
                
                $querySpecification.IntervalId = $intervalId 
                $querySpecification.IntervalIdSpecified = $True
                $querySpecification.Format = "normal"
                $querySpecification.MetricId = $perfMetricIds

                if($start) { 
                    $querySpecification.startTime = $start
                    $querySpecification.startTimeSpecified = $True
                }
                if($finish) {
                    $querySpecification.endTime = $finish
                    $querySpecification.endTimeSpecified = $True
                }
                $querySpecification
            }
        
            $retrievedStats =  $global:vimClient.VimService.QueryPerfComposite($vimServiceContent.perfManager,$pgsList)

            %{
                $retrievedStats.entity
                $retrievedStats.childEntity 
            } | where {$_.sampleInfo} | %{
                $retrievedStat = $_
                [array]$arrSampleInfo = $retrievedStat.sampleInfo
                $retrievedStat.Value |  %{
                    $retrievedStatInstance = $_
                    $Unit = $hashCounterLookupReverse.($retrievedStatInstance.id.counterId).unitInfo.label
                    for($i=0;$i -lt $arrSampleInfo.count;$i++) {
                        $retrievedStatInstance.Value[$i] | Select @{n="MetricId";e={$hashCounterLookupReverse.($retrievedStatInstance.id.counterId).FullCounterName}},
                                                          @{n="Timestamp";e={$arrSampleInfo[$i].Timestamp}},
                                                          @{n="Entity";e={$hashEntityLookup.($retrievedStat.Entity.Value).Entity.Name}},
                                                          @{n="EntityId";e={"$($retrievedStat.Entity.Type)-$($retrievedStat.Entity.Value)"}},
                                                          @{n="IntervalSecs";e={$arrSampleInfo[$i].Interval}},
                                                          @{n="Unit";e={$Unit}},
                                                          @{n="Instance";e={$retrievedStatInstance.id.Instance}},
                                                          @{n="Value";e={ if($Unit -eq "Percent") { $_/100 } else { $_ }}}
                    }
                }
            }
        }
    }
}



