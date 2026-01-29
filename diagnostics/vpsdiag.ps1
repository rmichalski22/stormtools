#Requires -Version 5.1
<#
.SYNOPSIS
    VPS Performance Diagnostics Tool
    
.DESCRIPTION
    Interactive PowerShell script to collect comprehensive system performance
    statistics and diagnostics for Windows Server VPS environments.
    
.NOTES
    Author: VPS Hosting Support
    Version: 1.0
    Requires: PowerShell 5.1 or later, Administrator privileges
#>

# Ensure script runs with administrator privileges
#Requires -RunAsAdministrator

# Set error action preference
$ErrorActionPreference = "Continue"

# Global variables
$script:DiagnosticsData = @{}
$script:OutputPath = "$env:TEMP\VPS-Diagnostics"
$script:Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:ServerName = $env:COMPUTERNAME

# Create output directory if it doesn't exist
if (-not (Test-Path $script:OutputPath)) {
    New-Item -ItemType Directory -Path $script:OutputPath -Force | Out-Null
}

#region Helper Functions

function Write-ColorOutput {
    <#
    .SYNOPSIS
        Writes colored output to console
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host -Object $Message -ForegroundColor $Color
}

function Write-Header {
    <#
    .SYNOPSIS
        Writes a formatted header to console
    #>
    param([string]$Title)
    
    Write-Host ""
    Write-ColorOutput "===============================================================" "Cyan"
    Write-ColorOutput "  $Title" "Cyan"
    Write-ColorOutput "===============================================================" "Cyan"
    Write-Host ""
}

function Get-SystemInformation {
    <#
    .SYNOPSIS
        Collects basic system information
    #>
    Write-ColorOutput "[*] Collecting system information..." "Yellow"
    
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $cs = Get-CimInstance Win32_ComputerSystem
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $bios = Get-CimInstance Win32_BIOS
        
        $uptime = (Get-Date) - $os.LastBootUpTime
        
        $systemInfo = [PSCustomObject]@{
            ServerName = $cs.Name
            OSVersion = $os.Caption
            OSBuild = $os.BuildNumber
            OSArchitecture = $os.OSArchitecture
            InstallDate = $os.InstallDate
            LastBootTime = $os.LastBootUpTime
            Uptime = "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m"
            TotalPhysicalMemoryGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
            NumberOfProcessors = $cs.NumberOfProcessors
            NumberOfLogicalProcessors = $cs.NumberOfLogicalProcessors
            ProcessorName = $cpu.Name
            ProcessorMaxClockSpeed = $cpu.MaxClockSpeed
            Manufacturer = $cs.Manufacturer
            Model = $cs.Model
            BIOSVersion = $bios.SMBIOSBIOSVersion
            TimeZone = (Get-TimeZone).DisplayName
            CollectionTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        
        $script:DiagnosticsData.SystemInformation = $systemInfo
        Write-ColorOutput "[OK] System information collected" "Green"
        return $systemInfo
    }
    catch {
        Write-ColorOutput "[!] Error collecting system information: $($_.Exception.Message)" "Red"
        return $null
    }
}

function Get-CPUStatistics {
    <#
    .SYNOPSIS
        Collects current CPU usage statistics
    #>
    param([int]$SampleCount = 5)
    
    $msg = "[*] Collecting CPU statistics (taking $SampleCount samples)..."
    Write-ColorOutput -Message $msg -Color "Yellow"
    
    try {
        $cpuSamples = @()
        
        for ($i = 1; $i -le $SampleCount; $i++) {
            $cpu = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1
            $cpuSamples += $cpu.CounterSamples[0].CookedValue
            Write-Progress -Activity "Collecting CPU samples" -Status "Sample $i of $SampleCount" -PercentComplete (($i / $SampleCount) * 100)
        }
        
        Write-Progress -Activity "Collecting CPU samples" -Completed
        
        $cpuStats = [PSCustomObject]@{
            AverageCPU = [math]::Round(($cpuSamples | Measure-Object -Average).Average, 2)
            MinimumCPU = [math]::Round(($cpuSamples | Measure-Object -Minimum).Minimum, 2)
            MaximumCPU = [math]::Round(($cpuSamples | Measure-Object -Maximum).Maximum, 2)
            Samples = $cpuSamples
            SampleCount = $SampleCount
        }
        
        $script:DiagnosticsData.CPUStatistics = $cpuStats
        Write-ColorOutput "[OK] CPU statistics collected - Avg: $($cpuStats.AverageCPU)%" "Green"
        return $cpuStats
    }
    catch {
        Write-ColorOutput "[!] Error collecting CPU statistics: $($_.Exception.Message)" "Red"
        return $null
    }
}

function Get-MemoryStatistics {
    <#
    .SYNOPSIS
        Collects memory usage statistics
    #>
    Write-ColorOutput "[*] Collecting memory statistics..." "Yellow"
    
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $totalMemoryGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $usedMemoryGB = $totalMemoryGB - $freeMemoryGB
        $memoryUsagePercent = [math]::Round(($usedMemoryGB / $totalMemoryGB) * 100, 2)
        
        # Get committed memory
        $perfMem = Get-Counter '\Memory\Committed Bytes' -SampleInterval 1 -MaxSamples 1
        $committedGB = [math]::Round($perfMem.CounterSamples[0].CookedValue / 1GB, 2)
        
        # Get page file usage
        $pageFile = Get-CimInstance Win32_PageFileUsage
        $pageFileSizeGB = if ($pageFile) { [math]::Round($pageFile.AllocatedBaseSize / 1KB, 2) } else { 0 }
        $pageFileUsageGB = if ($pageFile) { [math]::Round($pageFile.CurrentUsage / 1KB, 2) } else { 0 }
        
        $memoryStats = [PSCustomObject]@{
            TotalMemoryGB = $totalMemoryGB
            UsedMemoryGB = $usedMemoryGB
            FreeMemoryGB = $freeMemoryGB
            MemoryUsagePercent = $memoryUsagePercent
            CommittedMemoryGB = $committedGB
            PageFileSizeGB = $pageFileSizeGB
            PageFileUsageGB = $pageFileUsageGB
        }
        
        $script:DiagnosticsData.MemoryStatistics = $memoryStats
        Write-ColorOutput "[OK] Memory statistics collected - Usage: $memoryUsagePercent%" "Green"
        return $memoryStats
    }
    catch {
        Write-ColorOutput "[!] Error collecting memory statistics: $($_.Exception.Message)" "Red"
        return $null
    }
}

function Get-DiskStatistics {
    <#
    .SYNOPSIS
        Collects disk usage and I/O statistics
    #>
    Write-ColorOutput "[*] Collecting disk statistics..." "Yellow"
    
    try {
        $diskInfo = @()
        $volumes = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }
        
        foreach ($volume in $volumes) {
            $driveLetter = $volume.DriveLetter
            
            # Get disk space information
            $sizeGB = [math]::Round($volume.Size / 1GB, 2)
            $freeGB = [math]::Round($volume.SizeRemaining / 1GB, 2)
            $usedGB = $sizeGB - $freeGB
            $usedPercent = if ($sizeGB -gt 0) { [math]::Round(($usedGB / $sizeGB) * 100, 2) } else { 0 }
            
            # Try to get physical disk info
            try {
                $partition = Get-Partition -DriveLetter $driveLetter -ErrorAction SilentlyContinue
                $physicalDisk = $null
                if ($partition) {
                    $physicalDisk = Get-PhysicalDisk -ErrorAction SilentlyContinue | 
                        Where-Object { $_.DeviceId -eq $partition.DiskNumber } | 
                        Select-Object -First 1
                }
            }
            catch {
                $physicalDisk = $null
            }
            
            $diskInfo += [PSCustomObject]@{
                DriveLetter = $driveLetter
                Label = $volume.FileSystemLabel
                FileSystem = $volume.FileSystem
                SizeGB = $sizeGB
                UsedGB = $usedGB
                FreeGB = $freeGB
                UsedPercent = $usedPercent
                HealthStatus = $volume.HealthStatus
                MediaType = if ($physicalDisk) { $physicalDisk.MediaType } else { "Unknown" }
            }
        }
        
        # Collect disk I/O statistics
        $diskCounters = @()
        $logicalDisks = Get-Counter '\LogicalDisk(*)\*' -ErrorAction SilentlyContinue | 
            Where-Object { $_.CounterSamples.Path -match '\\LogicalDisk\([A-Z]:\)\\' }
        
        if ($logicalDisks) {
            foreach ($sample in $logicalDisks.CounterSamples) {
                if ($sample.Path -match '\\LogicalDisk\(([A-Z]:)\)\\(.+)') {
                    $drive = $matches[1]
                    $counter = $matches[2]
                    
                    $existing = $diskCounters | Where-Object { $_.Drive -eq $drive }
                    if (-not $existing) {
                        $diskCounters += [PSCustomObject]@{
                            Drive = $drive
                            Counters = @{}
                        }
                        $existing = $diskCounters | Where-Object { $_.Drive -eq $drive }
                    }
                    
                    $existing.Counters[$counter] = [math]::Round($sample.CookedValue, 2)
                }
            }
        }
        
        $diskStats = [PSCustomObject]@{
            Volumes = $diskInfo
            IOStatistics = $diskCounters
        }
        
        $script:DiagnosticsData.DiskStatistics = $diskStats
        Write-ColorOutput "[OK] Disk statistics collected" "Green"
        return $diskStats
    }
    catch {
        Write-ColorOutput "[!] Error collecting disk statistics: $($_.Exception.Message)" "Red"
        return $null
    }
}

function Get-NetworkStatistics {
    <#
    .SYNOPSIS
        Collects network adapter statistics and connectivity information
    #>
    Write-ColorOutput "[*] Collecting network statistics..." "Yellow"
    
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
        $adapterStats = @()
        
        foreach ($adapter in $adapters) {
            # Get adapter statistics
            $stats = Get-NetAdapterStatistics -Name $adapter.Name -ErrorAction SilentlyContinue
            
            # Get IP configuration
            $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -ErrorAction SilentlyContinue |
                Where-Object { $_.AddressFamily -eq 'IPv4' } | Select-Object -First 1
            
            # Calculate bandwidth usage (bytes per second)
            $receivedMBps = if ($stats) { [math]::Round($stats.ReceivedBytes / 1MB, 2) } else { 0 }
            $sentMBps = if ($stats) { [math]::Round($stats.SentBytes / 1MB, 2) } else { 0 }
            
            $adapterStats += [PSCustomObject]@{
                Name = $adapter.Name
                InterfaceDescription = $adapter.InterfaceDescription
                Status = $adapter.Status
                LinkSpeed = $adapter.LinkSpeed
                MacAddress = $adapter.MacAddress
                IPv4Address = if ($ipConfig) { $ipConfig.IPAddress } else { "N/A" }
                ReceivedBytesMB = $receivedMBps
                SentBytesMB = $sentMBps
            }
        }
        
        # Test internet connectivity
        $connectivityTest = @{
            GoogleDNS = Test-Connection -ComputerName 8.8.8.8 -Count 2 -Quiet
            CloudflareDNS = Test-Connection -ComputerName 1.1.1.1 -Count 2 -Quiet
        }
        
        # Get active connections count
        $tcpConnections = Get-NetTCPConnection -ErrorAction SilentlyContinue
        $connectionStats = @{
            Established = ($tcpConnections | Where-Object { $_.State -eq 'Established' }).Count
            Listening = ($tcpConnections | Where-Object { $_.State -eq 'Listen' }).Count
            TimeWait = ($tcpConnections | Where-Object { $_.State -eq 'TimeWait' }).Count
            Total = $tcpConnections.Count
        }
        
        $networkStats = [PSCustomObject]@{
            Adapters = $adapterStats
            ConnectivityTest = $connectivityTest
            ConnectionStats = $connectionStats
        }
        
        $script:DiagnosticsData.NetworkStatistics = $networkStats
        Write-ColorOutput "[OK] Network statistics collected" "Green"
        return $networkStats
    }
    catch {
        Write-ColorOutput "[!] Error collecting network statistics: $($_.Exception.Message)" "Red"
        return $null
    }
}

function Get-TopProcesses {
    <#
    .SYNOPSIS
        Collects information about top resource-consuming processes
    #>
    param([int]$TopCount = 10)
    
    Write-ColorOutput "[*] Collecting top $TopCount resource-consuming processes..." "Yellow"
    
    try {
        # Get processes sorted by CPU
        $topCPU = Get-Process | 
            Sort-Object CPU -Descending | 
            Select-Object -First $TopCount |
            Select-Object ProcessName, Id, 
                @{Name='CPUSeconds';Expression={[math]::Round($_.CPU, 2)}},
                @{Name='WorkingSetMB';Expression={[math]::Round($_.WorkingSet / 1MB, 2)}},
                @{Name='Threads';Expression={$_.Threads.Count}},
                StartTime
        
        # Get processes sorted by Memory
        $topMemory = Get-Process | 
            Sort-Object WorkingSet -Descending | 
            Select-Object -First $TopCount |
            Select-Object ProcessName, Id,
                @{Name='CPUSeconds';Expression={[math]::Round($_.CPU, 2)}},
                @{Name='WorkingSetMB';Expression={[math]::Round($_.WorkingSet / 1MB, 2)}},
                @{Name='Threads';Expression={$_.Threads.Count}},
                StartTime
        
        $processStats = [PSCustomObject]@{
            TopCPUProcesses = $topCPU
            TopMemoryProcesses = $topMemory
            TotalProcessCount = (Get-Process).Count
        }
        
        $script:DiagnosticsData.TopProcesses = $processStats
        Write-ColorOutput "[OK] Top processes collected" "Green"
        return $processStats
    }
    catch {
        Write-ColorOutput "[!] Error collecting process information: $($_.Exception.Message)" "Red"
        return $null
    }
}

function Get-ServiceStatus {
    <#
    .SYNOPSIS
        Collects information about Windows services, especially failed or stopped critical services
    #>
    Write-ColorOutput "[*] Collecting service status information..." "Yellow"
    
    try {
        # Get all services
        $services = Get-Service
        
        # Critical services that should typically be running
        $criticalServices = @(
            'W32Time', 'EventLog', 'RpcSs', 'DHCP', 'Dnscache', 
            'LanmanServer', 'LanmanWorkstation', 'Schedule', 'WinRM'
        )
        
        # Check critical services
        $criticalStatus = @()
        foreach ($serviceName in $criticalServices) {
            $service = $services | Where-Object { $_.Name -eq $serviceName }
            if ($service) {
                $criticalStatus += [PSCustomObject]@{
                    Name = $service.Name
                    DisplayName = $service.DisplayName
                    Status = $service.Status
                    StartType = $service.StartType
                }
            }
        }
        
        # Get stopped automatic services (potential issues)
        $stoppedAutoServices = $services | 
            Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' } |
            Select-Object Name, DisplayName, Status, StartType
        
        # Get failed services from event log (last 24 hours)
        $failedServices = @()
        try {
            $events = Get-WinEvent -FilterHashtable @{
                LogName = 'System'
                ProviderName = 'Service Control Manager'
                Level = 2  # Error
                StartTime = (Get-Date).AddHours(-24)
            } -MaxEvents 50 -ErrorAction SilentlyContinue
            
            foreach ($event in $events) {
                $failedServices += [PSCustomObject]@{
                    TimeCreated = $event.TimeCreated
                    Message = $event.Message.Substring(0, [Math]::Min(200, $event.Message.Length))
                }
            }
        }
        catch {
            # Event log query failed, continue without it
        }
        
        $serviceStats = [PSCustomObject]@{
            TotalServices = $services.Count
            RunningServices = ($services | Where-Object { $_.Status -eq 'Running' }).Count
            StoppedServices = ($services | Where-Object { $_.Status -eq 'Stopped' }).Count
            CriticalServices = $criticalStatus
            StoppedAutomaticServices = $stoppedAutoServices
            RecentFailures = $failedServices
        }
        
        $script:DiagnosticsData.ServiceStatus = $serviceStats
        Write-ColorOutput "[OK] Service status collected" "Green"
        return $serviceStats
    }
    catch {
        Write-ColorOutput "[!] Error collecting service status: $($_.Exception.Message)" "Red"
        return $null
    }
}

function Get-EventLogErrors {
    <#
    .SYNOPSIS
        Collects recent critical errors from Windows Event Logs
    #>
    param([int]$Hours = 24, [int]$MaxEvents = 50)
    
    Write-ColorOutput "[*] Collecting event log errors from last $Hours hours..." "Yellow"
    
    try {
        $startTime = (Get-Date).AddHours(-$Hours)
        $errors = @()
        
        # System log errors
        try {
            $systemErrors = Get-WinEvent -FilterHashtable @{
                LogName = 'System'
                Level = 1,2  # Critical and Error
                StartTime = $startTime
            } -MaxEvents $MaxEvents -ErrorAction SilentlyContinue
            
            foreach ($event in $systemErrors) {
                $errors += [PSCustomObject]@{
                    LogName = 'System'
                    Level = $event.LevelDisplayName
                    TimeCreated = $event.TimeCreated
                    Source = $event.ProviderName
                    EventID = $event.Id
                    Message = $event.Message.Substring(0, [Math]::Min(300, $event.Message.Length))
                }
            }
        }
        catch {
            $msg = "Could not retrieve System log errors"
            Write-ColorOutput -Message $msg -Color "Red"
        }
        
        # Application log errors
        try {
            $appErrors = Get-WinEvent -FilterHashtable @{
                LogName = 'Application'
                Level = 1,2  # Critical and Error
                StartTime = $startTime
            } -MaxEvents $MaxEvents -ErrorAction SilentlyContinue
            
            foreach ($event in $appErrors) {
                $errors += [PSCustomObject]@{
                    LogName = 'Application'
                    Level = $event.LevelDisplayName
                    TimeCreated = $event.TimeCreated
                    Source = $event.ProviderName
                    EventID = $event.Id
                    Message = $event.Message.Substring(0, [Math]::Min(300, $event.Message.Length))
                }
            }
        }
        catch {
            $msg = "Could not retrieve Application log errors"
            Write-ColorOutput -Message $msg -Color "Red"
        }
        
        # Sort by time and take top errors
        $errors = $errors | Sort-Object TimeCreated -Descending | Select-Object -First $MaxEvents
        
        $eventLogStats = [PSCustomObject]@{
            ErrorCount = $errors.Count
            TimeRange = "$Hours hours"
            Errors = $errors
        }
        
        $script:DiagnosticsData.EventLogErrors = $eventLogStats
        Write-ColorOutput "[OK] Event log errors collected - Found $($errors.Count) errors" "Green"
        return $eventLogStats
    }
    catch {
        Write-ColorOutput "[!] Error collecting event log errors: $($_.Exception.Message)" "Red"
        return $null
    }
}

function Get-WindowsUpdateStatus {
    <#
    .SYNOPSIS
        Collects Windows Update status and pending updates
    #>
    Write-ColorOutput "[*] Collecting Windows Update status..." "Yellow"
    
    try {
        # Get Windows Update service status
        $wuService = Get-Service -Name wuauserv
        
        # Get last update installation time from event log
        $lastUpdate = $null
        try {
            $updateEvents = Get-WinEvent -FilterHashtable @{
                LogName = 'System'
                ProviderName = 'Microsoft-Windows-WindowsUpdateClient'
                Id = 19
            } -MaxEvents 1 -ErrorAction SilentlyContinue
            
            if ($updateEvents) {
                $lastUpdate = $updateEvents[0].TimeCreated
            }
        }
        catch {
            # Could not get update events
        }
        
        # Check for pending reboot
        $pendingReboot = $false
        $rebootReasons = @()
        
        # Check various registry keys for pending reboot
        if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
            $pendingReboot = $true
            $rebootReasons += "Component Based Servicing"
        }
        if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
            $pendingReboot = $true
            $rebootReasons += "Windows Update"
        }
        if (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue) {
            $pendingReboot = $true
            $rebootReasons += "Pending File Rename Operations"
        }
        
        $updateStatus = [PSCustomObject]@{
            WindowsUpdateService = $wuService.Status
            LastUpdateInstalled = $lastUpdate
            PendingReboot = $pendingReboot
            RebootReasons = $rebootReasons
        }
        
        $script:DiagnosticsData.WindowsUpdateStatus = $updateStatus
        Write-ColorOutput "[OK] Windows Update status collected" "Green"
        return $updateStatus
    }
    catch {
        Write-ColorOutput "[!] Error collecting Windows Update status: $($_.Exception.Message)" "Red"
        return $null
    }
}

function Get-SecuritySoftwareStatus {
    <#
    .SYNOPSIS
        Collects information about installed security software
    #>
    Write-ColorOutput "[*] Collecting security software status..." "Yellow"
    
    try {
        $securityInfo = @()
        
        # Check Windows Defender status
        try {
            $defenderStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
            if ($defenderStatus) {
                $securityInfo += [PSCustomObject]@{
                    Product = "Windows Defender"
                    Enabled = $defenderStatus.AntivirusEnabled
                    Updated = $defenderStatus.AntivirusSignatureLastUpdated
                    RealTimeProtection = $defenderStatus.RealTimeProtectionEnabled
                }
            }
        }
        catch {
            # Windows Defender not available or query failed
        }
        
        # Check for other antivirus products via WMI
        try {
            $avProducts = Get-CimInstance -Namespace "root/SecurityCenter2" -ClassName AntiVirusProduct -ErrorAction SilentlyContinue
            foreach ($av in $avProducts) {
                $securityInfo += [PSCustomObject]@{
                    Product = $av.displayName
                    Status = "Installed"
                    PathToSignedProductExe = $av.pathToSignedProductExe
                }
            }
        }
        catch {
            # SecurityCenter2 not available
        }
        
        # Check Windows Firewall status
        $firewallProfiles = @()
        try {
            $profiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
            foreach ($profile in $profiles) {
                $firewallProfiles += [PSCustomObject]@{
                    Name = $profile.Name
                    Enabled = $profile.Enabled
                    DefaultInboundAction = $profile.DefaultInboundAction
                    DefaultOutboundAction = $profile.DefaultOutboundAction
                }
            }
        }
        catch {
            # Firewall status not available
        }
        
        $securityStatus = [PSCustomObject]@{
            AntivirusProducts = $securityInfo
            FirewallProfiles = $firewallProfiles
        }
        
        $script:DiagnosticsData.SecuritySoftware = $securityStatus
        Write-ColorOutput "[OK] Security software status collected" "Green"
        return $securityStatus
    }
    catch {
        Write-ColorOutput "[!] Error collecting security software status: $($_.Exception.Message)" "Red"
        return $null
    }
}

function Start-ExtendedMonitoring {
    <#
    .SYNOPSIS
        Performs extended monitoring over a specified duration with periodic sampling
    #>
    param(
        [int]$DurationMinutes = 30,
        [int]$SampleIntervalSeconds = 60
    )
    
    Write-Header "Extended Monitoring - $DurationMinutes Minutes"
    Write-ColorOutput "Starting extended monitoring session..." "Yellow"
    Write-ColorOutput "Duration: $DurationMinutes minutes | Sample Interval: $SampleIntervalSeconds seconds" "Cyan"
    Write-ColorOutput "Press Ctrl+C to cancel monitoring early" "Gray"
    Write-Host ""
    
    $samples = @()
    $totalSamples = [math]::Ceiling(($DurationMinutes * 60) / $SampleIntervalSeconds)
    $startTime = Get-Date
    
    try {
        for ($i = 1; $i -le $totalSamples; $i++) {
            $currentTime = Get-Date
            $elapsed = ($currentTime - $startTime).TotalMinutes
            
            Write-Progress -Activity "Extended Monitoring in Progress" `
                -Status "Sample $i of $totalSamples (Elapsed: $([math]::Round($elapsed, 1)) min)" `
                -PercentComplete (($i / $totalSamples) * 100)
            
            # Collect performance data
            $cpuCounter = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1
            $memCounter = Get-Counter '\Memory\Available MBytes' -SampleInterval 1 -MaxSamples 1
            
            # Collect disk I/O for system drive (C:)
            $diskReadCounter = Get-Counter '\LogicalDisk(C:)\Disk Read Bytes/sec' -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue
            $diskWriteCounter = Get-Counter '\LogicalDisk(C:)\Disk Write Bytes/sec' -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue
            
            # Collect network I/O
            $netSentCounter = Get-Counter '\Network Interface(*)\Bytes Sent/sec' -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue
            $netRecvCounter = Get-Counter '\Network Interface(*)\Bytes Received/sec' -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue
            
            $sample = [PSCustomObject]@{
                Timestamp = $currentTime
                ElapsedMinutes = [math]::Round($elapsed, 2)
                CPUPercent = [math]::Round($cpuCounter.CounterSamples[0].CookedValue, 2)
                AvailableMemoryMB = [math]::Round($memCounter.CounterSamples[0].CookedValue, 2)
                DiskReadBytesPerSec = if ($diskReadCounter) { [math]::Round($diskReadCounter.CounterSamples[0].CookedValue, 2) } else { 0 }
                DiskWriteBytesPerSec = if ($diskWriteCounter) { [math]::Round($diskWriteCounter.CounterSamples[0].CookedValue, 2) } else { 0 }
                NetworkSentBytesPerSec = if ($netSentCounter) { [math]::Round(($netSentCounter.CounterSamples.CookedValue | Measure-Object -Sum).Sum, 2) } else { 0 }
                NetworkRecvBytesPerSec = if ($netRecvCounter) { [math]::Round(($netRecvCounter.CounterSamples.CookedValue | Measure-Object -Sum).Sum, 2) } else { 0 }
            }
            
            $samples += $sample
            
            # Display current sample
            $timeStr = $currentTime.ToString('HH:mm:ss')
            $sampleMsg = "  [$timeStr] CPU: $($sample.CPUPercent)% | Available Memory: $($sample.AvailableMemoryMB) MB"
            Write-ColorOutput -Message $sampleMsg -Color "Gray"
            
            # Wait for next sample (unless it's the last one)
            if ($i -lt $totalSamples) {
                Start-Sleep -Seconds $SampleIntervalSeconds
            }
        }
        
        Write-Progress -Activity "Extended Monitoring in Progress" -Completed
        
        # Calculate statistics
        $cpuValues = $samples | ForEach-Object { $_.CPUPercent }
        $memValues = $samples | ForEach-Object { $_.AvailableMemoryMB }
        
        $monitoringResults = [PSCustomObject]@{
            StartTime = $startTime
            EndTime = Get-Date
            DurationMinutes = $DurationMinutes
            SampleIntervalSeconds = $SampleIntervalSeconds
            TotalSamples = $samples.Count
            Samples = $samples
            Statistics = [PSCustomObject]@{
                CPU = [PSCustomObject]@{
                    Average = [math]::Round(($cpuValues | Measure-Object -Average).Average, 2)
                    Minimum = [math]::Round(($cpuValues | Measure-Object -Minimum).Minimum, 2)
                    Maximum = [math]::Round(($cpuValues | Measure-Object -Maximum).Maximum, 2)
                }
                AvailableMemoryMB = [PSCustomObject]@{
                    Average = [math]::Round(($memValues | Measure-Object -Average).Average, 2)
                    Minimum = [math]::Round(($memValues | Measure-Object -Minimum).Minimum, 2)
                    Maximum = [math]::Round(($memValues | Measure-Object -Maximum).Maximum, 2)
                }
            }
        }
        
        $script:DiagnosticsData.ExtendedMonitoring = $monitoringResults
        
        Write-Host ""
        Write-ColorOutput "[OK] Extended monitoring completed" "Green"
        $avgMsg = "    Average CPU: $($monitoringResults.Statistics.CPU.Average)% (Min: $($monitoringResults.Statistics.CPU.Minimum)%, Max: $($monitoringResults.Statistics.CPU.Maximum)%)"
        Write-ColorOutput -Message $avgMsg -Color "Cyan"
        Write-ColorOutput "    Average Available Memory: $($monitoringResults.Statistics.AvailableMemoryMB.Average) MB" "Cyan"
        
        return $monitoringResults
    }
    catch {
        Write-ColorOutput "[!] Extended monitoring interrupted or failed: $($_.Exception.Message)" "Red"
        return $null
    }
}

function Export-DiagnosticsReport {
    <#
    .SYNOPSIS
        Exports collected diagnostics data to JSON and HTML formats
    #>
    Write-Header "Exporting Diagnostics Report"
    
    try {
        $reportBaseName = "$script:ServerName-Diagnostics-$script:Timestamp"
        
        # Export JSON
        $jsonPath = Join-Path $script:OutputPath "$reportBaseName.json"
        $script:DiagnosticsData | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8
        Write-ColorOutput "[OK] JSON report exported: $jsonPath" "Green"
        
        # Generate HTML report
        $htmlPath = Join-Path $script:OutputPath "$reportBaseName.html"
        $html = New-HTMLReport
        $html | Out-File -FilePath $htmlPath -Encoding UTF8
        Write-ColorOutput "[OK] HTML report exported: $htmlPath" "Green"
        
        # Create compressed archive
        $zipPath = Join-Path $script:OutputPath "$reportBaseName.zip"
        
        # Remove old zip if exists
        if (Test-Path $zipPath) {
            Remove-Item $zipPath -Force
        }
        
        Compress-Archive -Path $jsonPath, $htmlPath -DestinationPath $zipPath -CompressionLevel Optimal
        Write-ColorOutput "[OK] Compressed archive created: $zipPath" "Green"
        
        # Display file sizes
        $zipSize = [math]::Round((Get-Item $zipPath).Length / 1KB, 2)
        Write-Host ""
        Write-ColorOutput "Archive Size: $zipSize KB" "Cyan"
        Write-Host ""
        Write-ColorOutput "===============================================================" "Yellow"
        Write-ColorOutput "  UPLOAD THIS FILE TO YOUR SUPPORT TICKET:" "Yellow"
        Write-ColorOutput "  $zipPath" "White"
        Write-ColorOutput "===============================================================" "Yellow"
        Write-Host ""
        
        return $zipPath
    }
    catch {
        Write-ColorOutput "[!] Error exporting diagnostics report: $($_.Exception.Message)" "Red"
        return $null
    }
}

function New-HTMLReport {
    <#
    .SYNOPSIS
        Generates an HTML report from collected diagnostics data
    #>
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>VPS Diagnostics Report - $script:ServerName</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background-color: white;
            padding: 30px;
            box-shadow: 0 0 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #2c3e50;
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
        }
        h2 {
            color: #34495e;
            margin-top: 30px;
            border-bottom: 2px solid #95a5a6;
            padding-bottom: 5px;
        }
        h3 {
            color: #7f8c8d;
            margin-top: 20px;
        }
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }
        .info-box {
            background-color: #ecf0f1;
            padding: 15px;
            border-radius: 5px;
            border-left: 4px solid #3498db;
        }
        .info-label {
            font-weight: bold;
            color: #2c3e50;
        }
        .info-value {
            color: #34495e;
            margin-top: 5px;
        }
        .warning {
            background-color: #fff3cd;
            border-left: 4px solid #ffc107;
            padding: 15px;
            margin: 15px 0;
            border-radius: 5px;
        }
        .error {
            background-color: #f8d7da;
            border-left: 4px solid #dc3545;
            padding: 15px;
            margin: 15px 0;
            border-radius: 5px;
        }
        .success {
            background-color: #d4edda;
            border-left: 4px solid #28a745;
            padding: 15px;
            margin: 15px 0;
            border-radius: 5px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        th {
            background-color: #3498db;
            color: white;
            font-weight: bold;
        }
        tr:hover {
            background-color: #f5f5f5;
        }
        .metric-high {
            color: #dc3545;
            font-weight: bold;
        }
        .metric-medium {
            color: #ffc107;
            font-weight: bold;
        }
        .metric-low {
            color: #28a745;
            font-weight: bold;
        }
        .timestamp {
            color: #7f8c8d;
            font-size: 0.9em;
        }
        .chart-container {
            margin: 20px 0;
            padding: 15px;
            background-color: #f8f9fa;
            border-radius: 5px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>VPS Diagnostics Report</h1>
        <p class="timestamp">Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
"@

    # System Information Section
    if ($script:DiagnosticsData.SystemInformation) {
        $sysInfo = $script:DiagnosticsData.SystemInformation
        $html += @"
        <h2>System Information</h2>
        <div class="info-grid">
            <div class="info-box">
                <div class="info-label">Server Name</div>
                <div class="info-value">$($sysInfo.ServerName)</div>
            </div>
            <div class="info-box">
                <div class="info-label">Operating System</div>
                <div class="info-value">$($sysInfo.OSVersion) (Build $($sysInfo.OSBuild))</div>
            </div>
            <div class="info-box">
                <div class="info-label">Uptime</div>
                <div class="info-value">$($sysInfo.Uptime)</div>
            </div>
            <div class="info-box">
                <div class="info-label">Total Memory</div>
                <div class="info-value">$($sysInfo.TotalPhysicalMemoryGB) GB</div>
            </div>
            <div class="info-box">
                <div class="info-label">Processor</div>
                <div class="info-value">$($sysInfo.ProcessorName)</div>
            </div>
            <div class="info-box">
                <div class="info-label">Logical Processors</div>
                <div class="info-value">$($sysInfo.NumberOfLogicalProcessors)</div>
            </div>
        </div>
"@
    }

    # CPU Statistics
    if ($script:DiagnosticsData.CPUStatistics) {
        $cpuStats = $script:DiagnosticsData.CPUStatistics
        $cpuClass = if ($cpuStats.AverageCPU -gt 80) { "metric-high" } elseif ($cpuStats.AverageCPU -gt 60) { "metric-medium" } else { "metric-low" }
        
        $html += @"
        <h2>CPU Statistics</h2>
        <div class="info-grid">
            <div class="info-box">
                <div class="info-label">Average CPU Usage</div>
                <div class="info-value $cpuClass">$($cpuStats.AverageCPU)%</div>
            </div>
            <div class="info-box">
                <div class="info-label">Minimum CPU Usage</div>
                <div class="info-value">$($cpuStats.MinimumCPU)%</div>
            </div>
            <div class="info-box">
                <div class="info-label">Maximum CPU Usage</div>
                <div class="info-value">$($cpuStats.MaximumCPU)%</div>
            </div>
        </div>
"@
    }

    # Memory Statistics
    if ($script:DiagnosticsData.MemoryStatistics) {
        $memStats = $script:DiagnosticsData.MemoryStatistics
        $memClass = if ($memStats.MemoryUsagePercent -gt 90) { "metric-high" } elseif ($memStats.MemoryUsagePercent -gt 75) { "metric-medium" } else { "metric-low" }
        
        $html += @"
        <h2>Memory Statistics</h2>
        <div class="info-grid">
            <div class="info-box">
                <div class="info-label">Memory Usage</div>
                <div class="info-value $memClass">$($memStats.MemoryUsagePercent)%</div>
            </div>
            <div class="info-box">
                <div class="info-label">Used Memory</div>
                <div class="info-value">$($memStats.UsedMemoryGB) GB</div>
            </div>
            <div class="info-box">
                <div class="info-label">Free Memory</div>
                <div class="info-value">$($memStats.FreeMemoryGB) GB</div>
            </div>
            <div class="info-box">
                <div class="info-label">Committed Memory</div>
                <div class="info-value">$($memStats.CommittedMemoryGB) GB</div>
            </div>
        </div>
"@
    }

    # Disk Statistics
    if ($script:DiagnosticsData.DiskStatistics) {
        $diskStats = $script:DiagnosticsData.DiskStatistics
        
        $html += "<h2>Disk Statistics</h2>"
        
        if ($diskStats.Volumes) {
            $html += "<h3>Volumes</h3><table><tr><th>Drive</th><th>Label</th><th>Size (GB)</th><th>Used (GB)</th><th>Free (GB)</th><th>Used %</th><th>Health</th></tr>"
            
            foreach ($volume in $diskStats.Volumes) {
                $usageClass = if ($volume.UsedPercent -gt 90) { "metric-high" } elseif ($volume.UsedPercent -gt 75) { "metric-medium" } else { "metric-low" }
                $html += "<tr><td>$($volume.DriveLetter):</td><td>$($volume.Label)</td><td>$($volume.SizeGB)</td><td>$($volume.UsedGB)</td><td>$($volume.FreeGB)</td><td class='$usageClass'>$($volume.UsedPercent)%</td><td>$($volume.HealthStatus)</td></tr>"
            }
            
            $html += "</table>"
        }
    }

    # Top Processes
    if ($script:DiagnosticsData.TopProcesses) {
        $procStats = $script:DiagnosticsData.TopProcesses
        
        $html += "<h2>Top Resource-Consuming Processes</h2>"
        
        if ($procStats.TopCPUProcesses) {
            $html += "<h3>Top CPU Processes</h3><table><tr><th>Process Name</th><th>PID</th><th>CPU (seconds)</th><th>Memory (MB)</th><th>Threads</th></tr>"
            
            foreach ($proc in $procStats.TopCPUProcesses) {
                $html += "<tr><td>$($proc.ProcessName)</td><td>$($proc.Id)</td><td>$($proc.CPUSeconds)</td><td>$($proc.WorkingSetMB)</td><td>$($proc.Threads)</td></tr>"
            }
            
            $html += "</table>"
        }
        
        if ($procStats.TopMemoryProcesses) {
            $html += "<h3>Top Memory Processes</h3><table><tr><th>Process Name</th><th>PID</th><th>Memory (MB)</th><th>CPU (seconds)</th><th>Threads</th></tr>"
            
            foreach ($proc in $procStats.TopMemoryProcesses) {
                $html += "<tr><td>$($proc.ProcessName)</td><td>$($proc.Id)</td><td>$($proc.WorkingSetMB)</td><td>$($proc.CPUSeconds)</td><td>$($proc.Threads)</td></tr>"
            }
            
            $html += "</table>"
        }
    }

    # Event Log Errors
    if ($script:DiagnosticsData.EventLogErrors -and $script:DiagnosticsData.EventLogErrors.Errors.Count -gt 0) {
        $eventStats = $script:DiagnosticsData.EventLogErrors
        
        $html += "<h2>Recent Event Log Errors</h2>"
        $html += "<div class='warning'>Found $($eventStats.ErrorCount) errors in the last $($eventStats.TimeRange)</div>"
        $html += "<table><tr><th>Time</th><th>Log</th><th>Level</th><th>Source</th><th>Event ID</th><th>Message</th></tr>"
        
        foreach ($event in $eventStats.Errors | Select-Object -First 20) {
            $html += "<tr><td>$($event.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))</td><td>$($event.LogName)</td><td>$($event.Level)</td><td>$($event.Source)</td><td>$($event.EventID)</td><td>$($event.Message)</td></tr>"
        }
        
        $html += "</table>"
    }

    # Extended Monitoring
    if ($script:DiagnosticsData.ExtendedMonitoring) {
        $extStats = $script:DiagnosticsData.ExtendedMonitoring
        
        $html += "<h2>Extended Monitoring Results</h2>"
        $html += @"
        <div class="info-grid">
            <div class="info-box">
                <div class="info-label">Duration</div>
                <div class="info-value">$($extStats.DurationMinutes) minutes</div>
            </div>
            <div class="info-box">
                <div class="info-label">Total Samples</div>
                <div class="info-value">$($extStats.TotalSamples)</div>
            </div>
            <div class="info-box">
                <div class="info-label">Average CPU</div>
                <div class="info-value">$($extStats.Statistics.CPU.Average)%</div>
            </div>
            <div class="info-box">
                <div class="info-label">Peak CPU</div>
                <div class="info-value">$($extStats.Statistics.CPU.Maximum)%</div>
            </div>
        </div>
"@
    }

    # Close HTML
    $html += @"
    </div>
</body>
</html>
"@

    return $html
}

function Show-MainMenu {
    <#
    .SYNOPSIS
        Displays the main interactive menu
    #>
    
    Clear-Host
    Write-Header "VPS Performance Diagnostics Tool"
    Write-ColorOutput "Server: $script:ServerName" "Cyan"
    Write-ColorOutput "Current Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "Cyan"
    Write-Host ""
    Write-ColorOutput "Please select an option:" "White"
    Write-Host ""
    Write-ColorOutput "  1. Quick Snapshot (Immediate diagnostics collection)" "White"
    Write-ColorOutput "  2. Extended Monitoring (30-minute performance monitoring)" "White"
    Write-ColorOutput "  3. Custom Extended Monitoring (Specify duration)" "White"
    Write-ColorOutput "  4. Full Diagnostics (Comprehensive system analysis)" "White"
    Write-ColorOutput "  5. Network Diagnostics Only" "White"
    Write-ColorOutput "  6. Disk Analysis Only" "White"
    Write-ColorOutput "  7. Process Analysis Only" "White"
    Write-ColorOutput "  8. View Previous Reports" "White"
    Write-ColorOutput "  9. Exit" "White"
    Write-Host ""
    Write-ColorOutput "===============================================================" "Cyan"
}

function Start-QuickSnapshot {
    <#
    .SYNOPSIS
        Performs a quick snapshot of system diagnostics
    #>
    Write-Header "Quick Snapshot"
    
    Get-SystemInformation
    Get-CPUStatistics -SampleCount 5
    Get-MemoryStatistics
    Get-DiskStatistics
    Get-NetworkStatistics
    Get-TopProcesses -TopCount 10
    
    Export-DiagnosticsReport
}

function Start-FullDiagnostics {
    <#
    .SYNOPSIS
        Performs comprehensive diagnostics collection
    #>
    Write-Header "Full Diagnostics Collection"
    
    Get-SystemInformation
    Get-CPUStatistics -SampleCount 10
    Get-MemoryStatistics
    Get-DiskStatistics
    Get-NetworkStatistics
    Get-TopProcesses -TopCount 15
    Get-ServiceStatus
    Get-EventLogErrors -Hours 48 -MaxEvents 100
    Get-WindowsUpdateStatus
    Get-SecuritySoftwareStatus
    
    Export-DiagnosticsReport
}

#endregion

#region Main Script Execution

# Display banner
Clear-Host
Write-Host ""
Write-ColorOutput "+===============================================================+" "Cyan"
Write-ColorOutput "|                                                           |" "Cyan"
Write-ColorOutput "|        VPS PERFORMANCE DIAGNOSTICS TOOL v1.0              |" "Cyan"
Write-ColorOutput "|                                                           |" "Cyan"
Write-ColorOutput "+===============================================================+" "Cyan"
Write-Host ""
Write-ColorOutput "This tool will collect comprehensive diagnostics about your VPS" "White"
Write-ColorOutput "and generate a report that you can upload to your support ticket." "White"
Write-Host ""

# Main menu loop
$running = $true
while ($running) {
    Show-MainMenu
    $choice = Read-Host "Enter your choice (1-9)"
    
    switch ($choice) {
        "1" {
            # Quick Snapshot
            $script:DiagnosticsData = @{}
            Start-QuickSnapshot
            Write-Host ""
            Write-ColorOutput "Press any key to return to main menu..." "Gray"
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "2" {
            # Extended Monitoring (30 minutes)
            $script:DiagnosticsData = @{}
            Get-SystemInformation
            Start-ExtendedMonitoring -DurationMinutes 30 -SampleIntervalSeconds 60
            Get-TopProcesses -TopCount 15
            Export-DiagnosticsReport
            Write-Host ""
            Write-ColorOutput "Press any key to return to main menu..." "Gray"
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "3" {
            # Custom Extended Monitoring
            $script:DiagnosticsData = @{}
            Write-Host ""
            $duration = Read-Host 'Enter monitoring duration in minutes (e.g., 60)'
            if ($duration -match '^\d+$') {
                $durationInt = [int]$duration
                Get-SystemInformation
                Start-ExtendedMonitoring -DurationMinutes $durationInt -SampleIntervalSeconds 60
                Get-TopProcesses -TopCount 15
                Export-DiagnosticsReport
            } else {
                $msg = "Invalid duration. Please enter a number."
                Write-ColorOutput -Message $msg -Color "Red"
            }
            Write-Host ""
            Write-ColorOutput "Press any key to return to main menu..." "Gray"
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "4" {
            # Full Diagnostics
            $script:DiagnosticsData = @{}
            Start-FullDiagnostics
            Write-Host ""
            Write-ColorOutput "Press any key to return to main menu..." "Gray"
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "5" {
            # Network Diagnostics Only
            $script:DiagnosticsData = @{}
            Write-Header "Network Diagnostics"
            Get-SystemInformation
            Get-NetworkStatistics
            Export-DiagnosticsReport
            Write-Host ""
            Write-ColorOutput "Press any key to return to main menu..." "Gray"
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "6" {
            # Disk Analysis Only
            $script:DiagnosticsData = @{}
            Write-Header "Disk Analysis"
            Get-SystemInformation
            Get-DiskStatistics
            Export-DiagnosticsReport
            Write-Host ""
            Write-ColorOutput "Press any key to return to main menu..." "Gray"
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "7" {
            # Process Analysis Only
            $script:DiagnosticsData = @{}
            Write-Header "Process Analysis"
            Get-SystemInformation
            Get-TopProcesses -TopCount 20
            Export-DiagnosticsReport
            Write-Host ""
            Write-ColorOutput "Press any key to return to main menu..." "Gray"
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "8" {
            # View Previous Reports
            Write-Header "Previous Reports"
            $reports = Get-ChildItem -Path $script:OutputPath -Filter "*.zip" -ErrorAction SilentlyContinue
            if ($reports) {
                Write-ColorOutput "Found $($reports.Count) report(s):" "Green"
                Write-Host ""
                foreach ($report in $reports) {
                    $sizeMB = [math]::Round($report.Length / 1MB, 2)
                    Write-ColorOutput "  - $($report.Name) - $sizeMB MB - Created: $($report.CreationTime)" "White"
                }
                Write-Host ""
                Write-ColorOutput "Reports location: $script:OutputPath" "Cyan"
            } else {
                Write-ColorOutput "No previous reports found." "Yellow"
            }
            Write-Host ""
            Write-ColorOutput "Press any key to return to main menu..." "Gray"
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "9" {
            # Exit
            Write-Host ""
            Write-ColorOutput "Thank you for using VPS Diagnostics Tool!" "Green"
            Write-Host ""
            $running = $false
        }
        default {
            $msg = "Invalid choice. Please select 1-9."
            Write-ColorOutput -Message $msg -Color "Red"
            Start-Sleep -Seconds 2
        }
    }
}

#endregion