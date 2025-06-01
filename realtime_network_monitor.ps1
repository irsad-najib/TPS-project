# ===== REAL-TIME NETWORK MONITOR =====
# Monitor per 15 menit: Report /24 subnet details
# Monitor per 2 jam: Summary active subnets

param(
    [string]$BaseNetwork = "192.168.0.0",
    [int]$DetailIntervalMinutes = 15,
    [int]$SummaryIntervalHours = 2
)

# Global tracking variables
$global:subnet_activity = @{}
$global:device_history = @{}
$global:start_time = Get-Date
$global:detail_counter = 0
$global:summary_counter = 0

# Infrastructure filtering
$ROUTER_MACS = @("78:9A:18:99:EC:98", "78:9a:18:99:ec:98")
$INFRA_PREFIXES = @("78:9A:18", "E4:8D:8C", "DC:A6:32", "B8:27:EB")
$INFRA_VENDORS = @("Routerboard", "MikroTik", "Ubiquiti", "Cisco", "TP-Link")

# Logging with colors
function Write-TimedLog {
    param([string]$Message, [string]$Color = "White", [string]$Prefix = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp][$Prefix] $Message" -ForegroundColor $Color
}

# Check if device is infrastructure
function Is-Infrastructure {
    param([string]$MAC, [string]$Vendor)
    
    foreach ($router_mac in $ROUTER_MACS) {
        if ($MAC -eq $router_mac) { return $true }
    }
    
    foreach ($prefix in $INFRA_PREFIXES) {
        if ($MAC.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { 
            return $true 
        }
    }
    
    foreach ($infra_vendor in $INFRA_VENDORS) {
        if ($Vendor -like "*$infra_vendor*") { return $true }
    }
    
    return $false
}

# Get subnet from IP
function Get-Subnet {
    param([string]$IP)
    return ($IP -split '\.')[0..2] -join '.'
}

# Parse nmap scan results
function Parse-SubnetScan {
    param([string]$Subnet)
    
    Write-TimedLog "Scanning $Subnet.0/24..." "Yellow" "SCAN"
    $scan_result = nmap -sn "$Subnet.0/24" | Out-String
    
    $lines = $scan_result -split "`n"
    $devices = @()
    $current_ip = ""
    
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i].Trim()
        
        if ($line -match "Nmap scan report for (\d+\.\d+\.\d+\.\d+)") {
            $current_ip = $matches[1]
        }
        
        if ($line -match "MAC Address: ([A-Fa-f0-9:]{17}).*\((.*)\)") {
            $mac_address = $matches[1]
            $vendor = $matches[2]
            
            if (-not (Is-Infrastructure -MAC $mac_address -Vendor $vendor) -and $current_ip -ne "") {
                $device = [PSCustomObject]@{
                    IP = $current_ip
                    MAC = $mac_address
                    Vendor = $vendor
                    ScanTime = Get-Date
                }
                $devices += $device
            }
        }
    }
    
    return $devices
}

# Quick port check for active devices
function Quick-PortCheck {
    param([string]$IP)
    
    $port_result = nmap -sS -p 80,443,22,8080 $IP --open -T4 | Out-String
    $open_ports = @()
    
    $port_lines = $port_result -split "`n" | Where-Object { $_ -match "(\d+)/(tcp|udp)\s+open" }
    foreach ($port_line in $port_lines) {
        if ($port_line -match "(\d+)/(tcp|udp)\s+open") {
            $open_ports += $matches[1]
        }
    }
    
    return $open_ports
}

# Discover active subnets by scanning /16
function Discover-ActiveSubnets {
    param([bool]$FullScan = $false)
    
    Write-TimedLog "Discovering active subnets in $BaseNetwork/16..." "Cyan" "DISCOVERY"
    
    # Quick ping sweep to find active subnets
    $network_base = ($BaseNetwork -split '\.')[0..1] -join '.'
    $active_subnets = @()
    
    if ($FullScan) {
        # Full scan semua kemungkinan subnet (0-255)
        Write-TimedLog "Full scan mode: Testing all possible subnets..." "Yellow" "FULLSCAN"
        $test_ranges = 0..255
    } else {
        # Quick scan hanya common ranges
        $test_ranges = @(0, 1, 10, 20, 30, 50, 56, 100, 168, 192, 200, 210, 254)
    }
    
    foreach ($third_octet in $test_ranges) {
        $test_subnet = "$network_base.$third_octet"
        Write-TimedLog "Testing subnet $test_subnet.0/24..." "DarkGray" "TEST"
        
        # Quick scan beberapa IP di range tersebut
        $test_ips = @("$test_subnet.1", "$test_subnet.10", "$test_subnet.50", "$test_subnet.100", "$test_subnet.254")
        $subnet_active = $false
        
        foreach ($test_ip in $test_ips) {
            # Ping dengan timeout singkat
            $ping_result = nmap -sn $test_ip -T4 --host-timeout 2s | Out-String
            if ($ping_result -match "Host is up") {
                $subnet_active = $true
                break
            }
        }
        
        if ($subnet_active) {
            $active_subnets += $test_subnet
            Write-TimedLog "Active subnet found: $test_subnet.0/24" "Green" "FOUND"
        }
    }
    
    Write-TimedLog "Discovery completed: $($active_subnets.Count) active subnets found" "Cyan" "DISCOVERY"
    return $active_subnets
}

# Update subnet activity database
function Update-SubnetActivity {
    param([string]$Subnet, [array]$Devices)
    
    $current_time = Get-Date
    
    if (-not $global:subnet_activity.ContainsKey($Subnet)) {
        $global:subnet_activity[$Subnet] = @{
            FirstSeen = $current_time
            LastActive = $current_time
            DeviceCount = 0
            PeakDevices = 0
            TotalScans = 0
            CurrentDevices = @()
        }
    }
    
    $subnet_info = $global:subnet_activity[$Subnet]
    $subnet_info.LastActive = $current_time
    $subnet_info.DeviceCount = $Devices.Count
    $subnet_info.TotalScans++
    $subnet_info.CurrentDevices = $Devices
    
    if ($Devices.Count -gt $subnet_info.PeakDevices) {
        $subnet_info.PeakDevices = $Devices.Count
    }
    
    # Update device history
    foreach ($device in $Devices) {
        $device_key = $device.MAC
        if (-not $global:device_history.ContainsKey($device_key)) {
            $global:device_history[$device_key] = @{
                MAC = $device.MAC
                Vendor = $device.Vendor
                FirstSeen = $current_time
                LastSeen = $current_time
                IPHistory = @()
                Subnet = $Subnet
            }
        }
        
        $device_info = $global:device_history[$device_key]
        $device_info.LastSeen = $current_time
        if ($device.IP -notin $device_info.IPHistory) {
            $device_info.IPHistory += $device.IP
        }
    }
}

# Generate 15-minute detailed report
function Show-DetailedReport {
    $global:detail_counter++
    $runtime = [math]::Round(((Get-Date) - $global:start_time).TotalMinutes, 1)
    
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "          15-MINUTE DETAILED REPORT #$global:detail_counter" -ForegroundColor Cyan
    Write-Host "          Runtime: ${runtime} minutes" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
    
    if ($global:subnet_activity.Count -eq 0) {
        Write-TimedLog "No active subnets detected yet" "Yellow" "REPORT"
        return
    }
    
    foreach ($subnet in $global:subnet_activity.Keys | Sort-Object) {
        $info = $global:subnet_activity[$subnet]
        $age = [math]::Round(((Get-Date) - $info.LastActive).TotalMinutes, 1)
        
        Write-Host "`n[*] SUBNET: $subnet.0/24" -ForegroundColor Yellow
        Write-Host "   Status: " -NoNewline
        if ($age -lt 5) {
            Write-Host "[ACTIVE] (${age}m ago)" -ForegroundColor Green
        } elseif ($age -lt 15) {
            Write-Host "[RECENT] (${age}m ago)" -ForegroundColor Yellow
        } else {
            Write-Host "[INACTIVE] (${age}m ago)" -ForegroundColor Red
        }
        
        Write-Host "   Current Devices: $($info.DeviceCount) | Peak: $($info.PeakDevices) | Scans: $($info.TotalScans)"
        
        if ($info.CurrentDevices.Count -gt 0) {
            Write-Host "   Active Devices:" -ForegroundColor White
            foreach ($device in $info.CurrentDevices | Sort-Object IP) {
                Write-Host "     +-- $($device.IP) | $($device.MAC) | $($device.Vendor)" -ForegroundColor Gray
                
                # Quick port check for first few devices
                if ($info.CurrentDevices.IndexOf($device) -lt 3) {
                    $ports = Quick-PortCheck -IP $device.IP
                    if ($ports.Count -gt 0) {
                        Write-Host "        [PORTS] Open: $($ports -join ', ')" -ForegroundColor Magenta
                    }
                }
            }
        }
    }
    
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
}

# Generate 2-hour summary report
function Show-SummaryReport {
    $global:summary_counter++
    $runtime = [math]::Round(((Get-Date) - $global:start_time).TotalHours, 1)
    
    Write-Host "`n" + "="*80 -ForegroundColor Magenta
    Write-Host "                    2-HOUR SUMMARY REPORT #$global:summary_counter" -ForegroundColor Magenta
    Write-Host "                       Runtime: ${runtime} hours" -ForegroundColor Magenta
    Write-Host "="*80 -ForegroundColor Magenta
    
    # Active subnets summary
    $active_subnets = $global:subnet_activity.Keys | Sort-Object
    Write-Host "`n[NETWORK] OVERVIEW:" -ForegroundColor Cyan
    Write-Host "   Total Discovered Subnets: $($active_subnets.Count)" -ForegroundColor White
    Write-Host "   Total Unique Devices: $($global:device_history.Count)" -ForegroundColor White
    Write-Host "   Monitoring Duration: ${runtime} hours" -ForegroundColor White
    
    if ($active_subnets.Count -gt 0) {
        Write-Host "`n[STATS] SUBNET ACTIVITY RANKING:" -ForegroundColor Yellow
        
        $subnet_stats = @()
        foreach ($subnet in $active_subnets) {
            $info = $global:subnet_activity[$subnet]
            $last_active = [math]::Round(((Get-Date) - $info.LastActive).TotalMinutes, 1)
            
            $subnet_stats += [PSCustomObject]@{
                Subnet = "$subnet.0/24"
                PeakDevices = $info.PeakDevices
                CurrentDevices = $info.DeviceCount
                LastActive = "${last_active}m ago"
                TotalScans = $info.TotalScans
                Status = if ($last_active -lt 30) { "[ACTIVE]" } elseif ($last_active -lt 120) { "[RECENT]" } else { "[INACTIVE]" }
            }
        }
        
        $subnet_stats | Sort-Object PeakDevices -Descending | Format-Table -AutoSize
        
        Write-Host "[TOP] MOST ACTIVE SUBNETS:" -ForegroundColor Red
        $top_subnets = $subnet_stats | Sort-Object PeakDevices -Descending | Select-Object -First 3
        foreach ($top in $top_subnets) {
            Write-Host "   $($top.Subnet) - Peak: $($top.PeakDevices) devices, Status: $($top.Status)" -ForegroundColor White
        }
        
        Write-Host "`n[DEVICES] PERSISTENCE:" -ForegroundColor Green
        $persistent_devices = $global:device_history.Values | Where-Object {
            ((Get-Date) - $_.FirstSeen).TotalMinutes -gt 30 -and 
            ((Get-Date) - $_.LastSeen).TotalMinutes -lt 30
        }
        
        Write-Host "   Long-term active devices: $($persistent_devices.Count)" -ForegroundColor White
        foreach ($device in $persistent_devices | Select-Object -First 5) {
            $duration = [math]::Round(((Get-Date) - $device.FirstSeen).TotalMinutes, 1)
            Write-Host "   +-- $($device.MAC) ($($device.Vendor)) - Active for ${duration}m" -ForegroundColor Gray
        }
    }
    
    Write-Host "`n" + "="*80 -ForegroundColor Magenta
}

# Main monitoring loop
function Start-RealtimeMonitoring {
    Write-Host "[START] REAL-TIME NETWORK MONITOR" -ForegroundColor Green
    Write-Host "[CONFIG] Base Network: $BaseNetwork/16" -ForegroundColor White
    Write-Host "[CONFIG] Detail Reports: Every $DetailIntervalMinutes minutes" -ForegroundColor White
    Write-Host "[CONFIG] Summary Reports: Every $SummaryIntervalHours hours" -ForegroundColor White
    Write-Host "[CTRL] Press Ctrl+C to stop monitoring" -ForegroundColor Yellow
    Write-Host "="*60 -ForegroundColor Green
    
    $last_detail_time = Get-Date
    $last_summary_time = Get-Date
    $last_discovery_time = Get-Date
    $discovery_interval_minutes = 10  # Re-discover subnets every 10 minutes
    $cycle_counter = 0
    $current_subnets = @()
    
    try {
        while ($true) {
            $current_time = Get-Date
            $cycle_counter++
            
            # PHASE 1: Subnet Discovery (every 10 minutes or first run)
            if ($current_subnets.Count -eq 0 -or ($current_time - $last_discovery_time).TotalMinutes -ge $discovery_interval_minutes) {
                Write-Host "`n" + "-"*50 -ForegroundColor Blue
                Write-Host "CYCLE #$cycle_counter - SUBNET DISCOVERY PHASE" -ForegroundColor Blue
                Write-Host "-"*50 -ForegroundColor Blue
                
                # Alternate between quick and full scan
                $use_full_scan = ($cycle_counter % 3 -eq 0)  # Full scan every 3rd cycle
                $discovered_subnets = Discover-ActiveSubnets -FullScan $use_full_scan
                
                if ($discovered_subnets.Count -eq 0) {
                    Write-TimedLog "No active subnets found, using default subnet" "Yellow" "WARNING"
                    $discovered_subnets = @((Get-Subnet -IP "172.16.56.84"))
                }
                
                # Update current subnets list
                $current_subnets = $discovered_subnets
                $last_discovery_time = $current_time
                
                Write-TimedLog "Will monitor $($current_subnets.Count) subnets: $($current_subnets -join ', ')" "Cyan" "PLAN"
            }
            
            # PHASE 2: Detailed Device Scanning
            Write-Host "`n" + "-"*50 -ForegroundColor Green
            Write-Host "CYCLE #$cycle_counter - DEVICE SCANNING PHASE" -ForegroundColor Green
            Write-Host "-"*50 -ForegroundColor Green
            
            $total_devices_found = 0
            foreach ($subnet in $current_subnets) {
                Write-TimedLog "Scanning subnet $subnet.0/24 for devices..." "White" "SCAN"
                $devices = Parse-SubnetScan -Subnet $subnet
                Update-SubnetActivity -Subnet $subnet -Devices $devices
                
                if ($devices.Count -gt 0) {
                    Write-TimedLog "Found $($devices.Count) user devices in $subnet.0/24" "Green" "ACTIVE"
                    $total_devices_found += $devices.Count
                    
                    # Show devices found in this subnet
                    foreach ($device in $devices | Select-Object -First 3) {
                        Write-TimedLog "  Device: $($device.IP) | $($device.MAC) | $($device.Vendor)" "Gray" "DEVICE"
                    }
                    if ($devices.Count -gt 3) {
                        Write-TimedLog "  ... and $($devices.Count - 3) more devices" "Gray" "DEVICE"
                    }
                } else {
                    Write-TimedLog "No user devices found in $subnet.0/24" "DarkGray" "EMPTY"
                }
            }
            
            Write-TimedLog "Cycle #$cycle_counter completed: $total_devices_found total devices across $($current_subnets.Count) subnets" "Cyan" "SUMMARY"
            
            # PHASE 3: Check for reports
            if (($current_time - $last_detail_time).TotalMinutes -ge $DetailIntervalMinutes) {
                Show-DetailedReport
                $last_detail_time = $current_time
            }
            
            if (($current_time - $last_summary_time).TotalHours -ge $SummaryIntervalHours) {
                Show-SummaryReport
                $last_summary_time = $current_time
            }
            
            # Wait before next cycle
            Write-TimedLog "Waiting 60 seconds before next cycle..." "Gray" "WAIT"
            Start-Sleep -Seconds 60
        }
    } catch {
        Write-TimedLog "Monitoring stopped: $($_.Exception.Message)" "Red" "ERROR"
    } finally {
        Write-TimedLog "Final summary report:" "Yellow" "FINAL"
        Show-SummaryReport
        
        # Save final data
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $export_data = @{
            MonitoringInfo = @{
                StartTime = $global:start_time
                EndTime = Get-Date
                DetailReports = $global:detail_counter
                SummaryReports = $global:summary_counter
                TotalCycles = $cycle_counter
            }
            SubnetActivity = $global:subnet_activity
            DeviceHistory = $global:device_history
        }
        
        $filename = "network_monitor_$timestamp.json"
        $export_data | ConvertTo-Json -Depth 5 | Out-File -FilePath $filename -Encoding UTF8
        Write-TimedLog "Data saved to: $filename" "Green" "SAVED"
    }
}

# Start monitoring
Start-RealtimeMonitoring