$rg = Read-Host -Prompt "Resource group the vwan is in"
$vhubname = Read-Host -Prompt "vhub name to check effective routes"

# Define the export directory
$exportDirectory = Read-Host -Prompt "Path to save files to, default is c:\temp\vwanrouting"
if ([string]::IsNullOrWhiteSpace($exportDirectory))
    {
        $exportDirectory = "c:\temp\vwanrouting"
    }
    
# Ensure the export directory exists
if (-not (Test-Path -Path $exportDirectory)) {
    New-Item -Path $exportDirectory -ItemType Directory -Force
}
    


# Get hub route tables and their routes
$tablelist = Get-AzVHubRouteTable -ResourceGroupName $rg -VirtualHubName $vhubname | Select-Object -Property *
Write-Host "Collecting route table information for " $tablelist.Count " route tables"
$tableinfolist = @()
foreach ($table in $tablelist) {    
    $tstrt = $table.RoutesText | ConvertFrom-Json
    foreach ($route in $table.RoutesText) {        
        if($table.Routes.Count -eq 0) {
            $tableinfo = [PSCustomObject]@{
                RouteTableName = $table.Name;
                RouteTableId   = $table.Id;
                Label       = $table.Labels -join ",";                       
                RouteName = "";
                DestinationType = "";
                Destinations = "";
                NextHopType = "";
                NextHop = "";
                RoutesCount   = $table.Routes.Count;
                AssociatedConnections = ($table.AssociatedConnectionsText -join ","); 
                PropagatingConnections = ($table.PropagatingConnectionsText -join ",");
            }
            $tableinfolist += $tableinfo
        } elseif ($table.Routes.Count -gt 0) {
            foreach ($rt in $tstrt) {  
                $tableinfo = [PSCustomObject]@{
                RouteTableName = $table.Name;
                RouteTableId   = $table.Id;
                Label       = $table.Labels -join ",";                        
                RouteName = $rt.Name;
                DestinationType = $rt.DestinationType;
                Destinations = ($rt.Destinations -join ",");
                NextHopType = $rt.NextHopType;
                NextHop = $rt.NextHop;
                RoutesCount   = $table.Routes.Count;
                AssociatedConnections = ($table.AssociatedConnectionsText -join ","); 
                PropagatingConnections = ($table.PropagatingConnectionsText -join ",");
                }
                $tableinfolist += $tableinfo
            }
        }
    
    }
}
$tableinfolist | Export-Csv -Path "$exportDirectory\routetables.csv" -NoTypeInformation -Force
$staticlist99 = @()
$hub = Get-AzVirtualHub -ResourceGroupName $rg -Name $vhubname | Select-Object -Property *
foreach ($vnet in $hub.VirtualNetworkConnections) {
    $staticlist = @()
    Write-Host "Gathering static routes for VNet connection: " $vnet.name
    $vnetstatic = Get-AzVirtualHubVnetConnection -ResourceGroupName $rg -VirtualHubName $vhubname -Name $vnet.name | Select-Object -Property *
    foreach ($route in $vnetstatic.RoutingConfiguration.VnetRoutes.StaticRoutes) {                    
                $vnetroute = [PSCustomObject]@{
                    VNetConnectionName = $vnet.name;
                    RouteName        = $route.Name;
                    AddressPrefix     = ($route.AddressPrefixes -join ",");
                    NextHop           = $route.NextHopIpAddress;
                    AssociatedTable  = $vnetstatic.RoutingConfiguration.AssociatedRouteTable.Id;
                    PropagatedTables = $vnetstatic.RoutingConfiguration.PropagatedRouteTables.Ids.Id -join ",";
                    PropagatedLabels = ($vnetstatic.RoutingConfiguration.PropagatedRouteTables.Labels -join ",");
                }
                $staticlist += $vnetroute
                $staticlist99 += $vnetroute        
    }
    if ($null -ne $vnetroute){        
        $staticlist | Export-Csv -Path "$exportDirectory\vnetstaticroutes.csv" -Append -NoTypeInformation -Force
        }
    
}

# Now check for VPN Gateway, ExpressRoute Gateway, Route Maps and Routing Intent
Write-Host "Gathering VPN Gateway, Route Maps and Routing Intent information if applicable, this might take a few minutes"
if ($hub.ExpressRouteGateway){    
    $er1 = Get-AzExpressRouteConnection -ResourceGroupName $rg -ExpressRouteGatewayName ($hub.ExpressRouteGateway.Id -split "/")[-1] | Select-Object -Property *
    $erlist = @()
    foreach ($conn in $er1) {                    
                $erconn = [PSCustomObject]@{
                    ExrCircuitID = $conn.ExpressRouteCircuitPeering.Id;
                    ConnectionName        = $conn.Name;                    
                    AssociatedTable  = $conn.RoutingConfiguration.AssociatedRouteTable.Id;
                    PropagatedTables = $conn.RoutingConfiguration.PropagatedRouteTables.Ids.Id -join ",";
                    PropagatedLabels = ($conn.RoutingConfiguration.PropagatedRouteTables.Labels -join ",");
                }
                $erlist += $erconn
        
            # Extract the circuit name
            $circuitName = (($conn.ExpressRouteCircuitPeering.Id -split "/expressRouteCircuits/")[1] -split "/")[0]
            $peeringName = ($conn.ExpressRouteCircuitPeering.Id -split "/")[-1]
            $rgname = ($conn.ExpressRouteCircuitPeering.Id -split "/")[4]
            #Write-Output $rgname
            #Write-Output $peeringName
            #Write-Output $circuitName
            try {
                $exrRoutespri = Get-AzExpressRouteCircuitRouteTable -ResourceGroupName $rgname -ExpressRouteCircuitName $circuitName -PeeringType $peeringName -DevicePath 'Primary'
                $exrRoutespri | Export-Csv -Path "$exportDirectory\exr-routetable-primary.csv" -Append -NoTypeInformation -Force
                $exrRoutessec = Get-AzExpressRouteCircuitRouteTable -ResourceGroupName $rgname -ExpressRouteCircuitName $circuitName -PeeringType $peeringName -DevicePath 'Secondary'
                $exrRoutessec | Export-Csv -Path "$exportDirectory\exr-routetable-secondary.csv" -Append -NoTypeInformation -Force                
            }
            catch {
                Write-Host "Error retrieving route table for circuit $circuitName peering $peeringName in resource group $rgname. $_"
            }
            
    }
    if ($null -ne $erconn){
        $erlist | Export-Csv -Path "$exportDirectory\exrconnection.csv" -Append -NoTypeInformation -Force
        }
    
}
if ($hub.VpnGateway){    
    $tst = $hub.VpnGateway.Id.tostring().Trim()    
    $web1 = Invoke-AzRestMethod -Method POST -Path $tst"/getlearnedroutes?api-version=2023-06-01"    
    do {
        start-sleep -Seconds 5
        $web2 = Invoke-AzRestMethod -Method GET -Uri $web1.Headers.Location.OriginalString        
    } until (
        ($web2.StatusCode = "200") -or ($web2.StatusCode = "500")
    )    
    $learnedroutes = $web2.Content | ConvertFrom-Json 
    if($null -ne $learnedroutes.value) {
        $learnedroutes.value | Export-Csv -Path "$exportDirectory\vpngw-learnedroutes.csv" -NoTypeInformation -Force
    }    
    $web3 = Invoke-AzRestMethod -Method POST -Path $tst"/getbgppeerstatus?api-version=2023-06-01"
    do {
        start-sleep -Seconds 5
        $web4 = Invoke-AzRestMethod -Method GET -Uri $web3.Headers.Location.OriginalString        
    } until (
        ($web4.StatusCode = "200") -or ($web4.StatusCode = "500")
    )
    $advertised1 = $web4.Content | ConvertFrom-Json
    $peertst = $advertised1.value.neighbor | Select-Object -Unique
    foreach($item in $peertst) {        
        $web5 = Invoke-AzRestMethod -Method POST -Path $tst"/getadvertisedroutes?api-version=2023-06-01&peer=$item"
        do {
            start-sleep -Seconds 5
            $web6 = Invoke-AzRestMethod -Method GET -Uri $web5.Headers.Location.OriginalString            
        } until (
            ($web6.StatusCode = "200") -or ($web6.StatusCode = "500")
        )        
        $advertised2 = $web6.Content | ConvertFrom-Json
        if ($null -ne $advertised2.value) {
            $advertised2.value | Export-Csv -Path "$exportDirectory\vpngw-advertisedroutes-to-peer-$($item).csv" -NoTypeInformation -Force
            
        }
        
        
    }
}
if ($hub.AzureFirewall){
    $RI = Get-AzRoutingIntent -ResourceGroupName $rg -VirtualHubName $vhubname | Select-Object -Property *
    if ($null -ne $RI) {
        $RIList = @()
        foreach ($policy in $RI.RoutingPolicies) {
            $policyinfo = [PSCustomObject]@{
                Name = $policy.Name;
                Destinations = $policy.Destinations -join ",";
                NextHopType = $policy.NextHopType;
                NextHop = $policy.NextHop;
                
            }
            $RIList += $policyinfo
        }
    }
    $RIList | Export-Csv -Path "$exportDirectory\routingintent.csv" -NoTypeInformation -Force    
}
$rm = Get-AzRouteMap -ResourceGroupName $rg -VirtualHubName $vhubname | select-object -Property *
if ($null -ne $rm){
    $routemaplist = @()
    foreach ($routemap in $rm) {
        $tst1 = $routemap.RouteMapRulesText | ConvertFrom-Json
        foreach ($rule in $tst1) {
        $routemapinfo = [PSCustomObject]@{
            Name = $routemap.Name;            
            Rule = $rule.Name;
            MatchCondition = $rule.MatchCriteria.MatchCondition;
            MatchRoutePrefix = $rule.MatchCriteria.RoutePrefix;
            MatchCommunity = $rule.MatchCriteria.Community;
            MatchASPath = $rule.MatchCriteria.ASPath;
            Type = $rule.Actions.Type;
            ActionsRoutePrefix = $rule.Actions.Parameters.RoutePrefix -join ",";
            ActionsCommunity = $rule.Actions.Parameters.Community -join ",";
            ActionsASPath = $rule.Actions.Parameters.ASPath -join ",";
            NextStepIfMatched = $rule.NextStepIfMatched;
            AssociatedInboundConnections = $routemap.AssociatedInboundConnectionsText -join ",";
            AssociatedOutboundConnections = $routemap.AssociatedOutboundConnectionsText -join ",";            
        }
        $routemaplist += $routemapinfo
        }
    }
    $routemaplist | Export-Csv -Path "$exportDirectory\routemaps.csv" -NoTypeInformation -Force
}
# Now get effective routes for each route table and Azure Firewall if applicable
$biglist = @()
foreach ($table in (Get-AzVHubRouteTable -ResourceGroupName $rg -VirtualHubName $vhubname)) {
    Write-Host "Gathering effective routes for route table: " $table.Name    
    $efroutes = Get-AzVHubEffectiveRoute -ResourceGroupName $rg -VirtualHubName $vhubname -VirtualWanResourceType "RouteTable" -Resourceid $table.Id
    ForEach ($route in $efroutes) {
        if ($route.Value) {
            foreach ($entry in $route.Value) {
                $Routes = [PSCustomObject]@{
                    RouteTableName     = $table.Name;
                    RouteTableId       = $table.Id;
                    AddressPrefix      = ($entry.AddressPrefixes -join ",")
                    NextHops           = ($entry.NextHops -join ",")
                    NextHopType        = $entry.NextHopType
                    NextHopIpAddress   = $staticlist99 | Where-Object {($_.AddressPrefix -in $entry.AddressPrefixes) } | Select-Object -ExpandProperty NextHop
                    AsPath             = $entry.AsPath
                    RouteOrigin        = $entry.RouteOrigin
                    RouterserviceIPsAddress = ($hub.VirtualRouterIps -join ",")
                }
                $biglist += $Routes
            }
        }
    }
    
}
$biglist | Export-Csv -Path "$exportDirectory\routetable-effectiveroutes.csv" -Append -NoTypeInformation -Force
if ($hub.AzureFirewall) {
    Write-Host "Gathering effective routes for Azure Firewall"
    $efroutes2 = Get-AzVHubEffectiveRoute -ResourceGroupName $rg -VirtualHubName $vhubname -VirtualWanResourceType "AzureFirewalls" -ResourceId $hub.AzureFirewall.Id
    $biglist2 = @()
    ForEach ($route in $efroutes2) {
        if ($route.Value) {
            foreach ($entry in $route.Value) {
                $Routes2 = [PSCustomObject]@{
                    AzureFirewllName     = "AzureFirewall";
                    AzureFirewallId       = $hub.AzureFirewall.Id;
                    AddressPrefix      = ($entry.AddressPrefixes -join ",")
                    NextHops           = ($entry.NextHops -join ",")
                    NextHopType        = $entry.NextHopType
                    NextHopIpAddress   = $staticlist99 | Where-Object {($_.AddressPrefix -in $entry.AddressPrefixes) } | Select-Object -ExpandProperty NextHop
                    AsPath             = $entry.AsPath
                    RouteOrigin        = $entry.RouteOrigin
                    RouterserviceIPsAddress = ($hub.VirtualRouterIps -join ",")
                }
                $biglist2 += $Routes2
            }
        }
    }
    $biglist2 | Export-Csv -Path "$exportDirectory\azurefirewall-effectiveroutes.csv" -Append -NoTypeInformation -Force
}