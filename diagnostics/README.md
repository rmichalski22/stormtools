# VPS Performance Diagnostics Tool - Technical Documentation

## Overview

This PowerShell script is an interactive diagnostic tool designed for Windows Server VPS environments (2019, 2022, 2025). It collects comprehensive system performance metrics, statistics, and diagnostic information to help support teams troubleshoot customer-reported performance issues.

## Purpose and Use Case

**Business Problem**: VPS hosting customers frequently report performance issues without providing technical details, making troubleshooting difficult and time-consuming.

**Solution**: This script provides customers with an easy-to-use tool that:
- Collects relevant system diagnostics automatically
- Requires minimal technical knowledge to operate
- Generates professional reports in multiple formats
- Creates a compressed archive ready for upload to support tickets

## System Requirements

- **Operating System**: Windows Server 2019, 2022, or 2025
- **PowerShell Version**: 5.1 or later
- **Privileges**: Must run as Administrator
- **Execution Policy**: Must allow script execution

## Script Architecture

### Global Variables

The script uses several script-scoped variables to maintain state:

- `$script:DiagnosticsData` - Hashtable storing all collected diagnostic data
- `$script:OutputPath` - Directory path for output files (`$env:TEMP\VPS-Diagnostics`)
- `$script:Timestamp` - Timestamp string for unique file naming (format: `yyyyMMdd-HHmmss`)
- `$script:ServerName` - Computer name from environment variable

### Core Functions

#### Helper Functions

1. **Write-ColorOutput**
   - **Purpose**: Writes colored text to console for better user experience
   - **Parameters**: Message (string), Color (string, default "White")
   - **Returns**: None (console output only)

2. **Write-Header**
   - **Purpose**: Displays formatted section headers with decorative borders
   - **Parameters**: Title (string)
   - **Returns**: None (console output only)

#### Data Collection Functions

3. **Get-SystemInformation**
   - **Purpose**: Collects basic system and hardware information
   - **Data Sources**: Win32_OperatingSystem, Win32_ComputerSystem, Win32_Processor, Win32_BIOS CIM classes
   - **Collected Data**:
     - Server name, OS version, build number, architecture
     - Installation date, last boot time, uptime calculation
     - Total physical memory in GB
     - Processor count (physical and logical)
     - Processor name and maximum clock speed
     - Manufacturer, model, BIOS version
     - Time zone and collection timestamp
   - **Returns**: PSCustomObject with system information
   - **Error Handling**: Try-catch block with user notification on failure

4. **Get-CPUStatistics**
   - **Purpose**: Measures CPU usage over multiple samples
   - **Parameters**: SampleCount (int, default 5)
   - **Data Sources**: Performance counter `\Processor(_Total)\% Processor Time`
   - **Sampling Method**: Collects samples at 1-second intervals
   - **Collected Data**:
     - Average CPU usage percentage
     - Minimum CPU usage across samples
     - Maximum CPU usage across samples
     - Array of all individual samples
   - **Progress Indication**: Shows progress bar during collection
   - **Returns**: PSCustomObject with CPU statistics
   - **Mathematical Operations**: Rounds values to 2 decimal places

5. **Get-MemoryStatistics**
   - **Purpose**: Collects comprehensive memory usage information
   - **Data Sources**: Win32_OperatingSystem CIM class, Performance counters, Win32_PageFileUsage
   - **Collected Data**:
     - Total visible memory in GB
     - Used memory in GB
     - Free memory in GB
     - Memory usage percentage
     - Committed memory in GB
     - Page file size and usage in GB
   - **Calculations**: Converts KB to GB, calculates usage percentages
   - **Returns**: PSCustomObject with memory statistics

6. **Get-DiskStatistics**
   - **Purpose**: Collects disk space, health, and I/O performance data
   - **Data Sources**: Get-Volume, Get-Partition, Get-PhysicalDisk, Performance counters
   - **Volume Information**:
     - Drive letter, label, file system
     - Size, used space, free space in GB
     - Usage percentage
     - Health status
     - Media type (SSD, HDD, etc.)
   - **I/O Statistics**: Collects performance counters for each logical disk
   - **Returns**: PSCustomObject containing volumes array and I/O statistics
   - **Error Handling**: Gracefully handles missing physical disk information

7. **Get-NetworkStatistics**
   - **Purpose**: Collects network adapter information and connectivity status
   - **Data Sources**: Get-NetAdapter, Get-NetAdapterStatistics, Get-NetIPAddress, Get-NetTCPConnection
   - **Adapter Information**:
     - Name, interface description, status
     - Link speed, MAC address
     - IPv4 address
     - Received and sent bytes (converted to MB)
   - **Connectivity Tests**: Pings Google DNS (8.8.8.8) and Cloudflare DNS (1.1.1.1)
   - **Connection Statistics**: Counts TCP connections by state (Established, Listening, TimeWait, Total)
   - **Returns**: PSCustomObject with network statistics
   - **Filtering**: Only includes active ("Up") network adapters

8. **Get-TopProcesses**
   - **Purpose**: Identifies processes consuming the most system resources
   - **Parameters**: TopCount (int, default 10)
   - **Data Sources**: Get-Process cmdlet
   - **Collected Data**:
     - Top CPU-consuming processes (sorted by CPU time)
     - Top memory-consuming processes (sorted by working set)
     - For each process: Name, PID, CPU seconds, memory MB, thread count, start time
     - Total process count
   - **Returns**: PSCustomObject with two arrays (TopCPUProcesses, TopMemoryProcesses)
   - **Memory Conversion**: Converts working set from bytes to MB

9. **Get-ServiceStatus**
   - **Purpose**: Monitors Windows services, especially critical services and failures
   - **Data Sources**: Get-Service cmdlet, Windows Event Log
   - **Critical Services Monitored**:
     - W32Time, EventLog, RpcSs, DHCP, Dnscache
     - LanmanServer, LanmanWorkstation, Schedule, WinRM
   - **Collected Data**:
     - Total service counts by status
     - Critical service status
     - Stopped automatic services (potential issues)
     - Recent service failures from event log (last 24 hours)
   - **Event Log Query**: Queries System log for Service Control Manager errors
   - **Returns**: PSCustomObject with service statistics
   - **Error Handling**: Continues if event log query fails

10. **Get-EventLogErrors**
    - **Purpose**: Collects recent critical errors and warnings from Windows Event Logs
    - **Parameters**: Hours (int, default 24), MaxEvents (int, default 50)
    - **Data Sources**: System and Application event logs
    - **Filters**: Events with level 1 (Critical) or 2 (Error)
    - **Collected Data**:
      - Log name (System or Application)
      - Event level (Critical/Error)
      - Time created
      - Source (provider name)
      - Event ID
      - Message (truncated to 300 characters)
    - **Processing**: Combines events from both logs, sorts by time, limits to MaxEvents
    - **Returns**: PSCustomObject with error count and errors array
    - **Error Handling**: Separate try-catch for each log to ensure partial data collection

11. **Get-WindowsUpdateStatus**
    - **Purpose**: Checks Windows Update service status and pending updates/reboots
    - **Data Sources**: Get-Service, Windows Event Log, Registry keys
    - **Collected Data**:
      - Windows Update service status
      - Last update installation time (from event log, Event ID 19)
      - Pending reboot status (boolean)
      - Reboot reasons (array)
    - **Registry Keys Checked**:
      - Component Based Servicing\RebootPending
      - WindowsUpdate\Auto Update\RebootRequired
      - Session Manager\PendingFileRenameOperations
    - **Returns**: PSCustomObject with update status
    - **Event Query**: Searches for WindowsUpdateClient Event ID 19

12. **Get-SecuritySoftwareStatus**
    - **Purpose**: Identifies installed security software and configurations
    - **Data Sources**: Get-MpComputerStatus, WMI SecurityCenter2, Get-NetFirewallProfile
    - **Windows Defender Data**:
      - Enabled status
      - Last signature update time
      - Real-time protection status
    - **Other Antivirus Products**: Queries WMI for third-party AV products
    - **Windows Firewall**: Status of all profiles (Domain, Private, Public)
    - **Returns**: PSCustomObject with security software information
    - **Error Handling**: Gracefully handles missing components (e.g., Defender not installed)

#### Advanced Monitoring Functions

13. **Start-ExtendedMonitoring**
    - **Purpose**: Performs long-duration performance monitoring with periodic sampling
    - **Parameters**: 
      - DurationMinutes (int, default 30)
      - SampleIntervalSeconds (int, default 60)
    - **Monitoring Process**:
      1. Calculates total number of samples needed
      2. Loops through collection period
      3. Collects performance counters each interval
      4. Displays progress and current metrics
      5. Allows Ctrl+C cancellation
    - **Performance Counters Collected**:
      - CPU usage percentage (Processor(_Total)\% Processor Time)
      - Available memory in MB
      - Disk read/write bytes per second (C: drive)
      - Network sent/received bytes per second (all interfaces)
    - **Statistical Analysis**:
      - Calculates average, minimum, maximum for CPU
      - Calculates average, minimum, maximum for available memory
    - **Returns**: PSCustomObject with samples array and statistics
    - **User Experience**: Shows real-time metrics, progress bar, timestamps
    - **Data Storage**: All samples stored in array for detailed analysis

#### Report Generation Functions

14. **Export-DiagnosticsReport**
    - **Purpose**: Exports collected data to multiple formats and creates uploadable archive
    - **Output Files**:
      - JSON file (machine-readable, full data structure, depth 10)
      - HTML file (human-readable, formatted report)
      - ZIP archive (compressed, contains both JSON and HTML)
    - **File Naming Convention**: `[ServerName]-Diagnostics-[Timestamp].[extension]`
    - **Process**:
      1. Converts DiagnosticsData hashtable to JSON
      2. Generates HTML report using New-HTMLReport function
      3. Compresses both files into ZIP archive
      4. Displays file sizes and upload instructions
    - **Returns**: Path to ZIP file
    - **User Communication**: Clear instructions with highlighted path to upload file

15. **New-HTMLReport**
    - **Purpose**: Creates formatted HTML report from collected diagnostics data
    - **Structure**: Complete HTML5 document with embedded CSS
    - **Styling**:
      - Responsive grid layout for information boxes
      - Color-coded metrics (red for high, yellow for medium, green for low)
      - Professional table formatting
      - Warning/error/success alert boxes
    - **Sections Generated**:
      - System Information (grid layout with key details)
      - CPU Statistics (with color-coded thresholds)
      - Memory Statistics (with usage indicators)
      - Disk Statistics (table with all volumes)
      - Top Processes (separate tables for CPU and memory)
      - Event Log Errors (if present, limited to 20 most recent)
      - Extended Monitoring Results (if performed)
    - **Threshold Logic**:
      - CPU: >80% red, >60% yellow, else green
      - Memory: >90% red, >75% yellow, else green
      - Disk: >90% red, >75% yellow, else green
    - **Returns**: Complete HTML string
    - **Conditional Rendering**: Only includes sections with collected data

#### User Interface Functions

16. **Show-MainMenu**
    - **Purpose**: Displays interactive menu with available options
    - **Menu Options**:
      1. Quick Snapshot (immediate diagnostics)
      2. Extended Monitoring (30-minute default)
      3. Custom Extended Monitoring (user-specified duration)
      4. Full Diagnostics (comprehensive analysis)
      5. Network Diagnostics Only
      6. Disk Analysis Only
      7. Process Analysis Only
      8. View Previous Reports
      9. Exit
    - **Display Elements**: Server name, current time, formatted menu with colors
    - **Returns**: None (displays menu only)

#### Workflow Functions

17. **Start-QuickSnapshot**
    - **Purpose**: Performs rapid diagnostic collection for immediate issues
    - **Functions Called**:
      - Get-SystemInformation
      - Get-CPUStatistics (5 samples)
      - Get-MemoryStatistics
      - Get-DiskStatistics
      - Get-NetworkStatistics
      - Get-TopProcesses (top 10)
      - Export-DiagnosticsReport
    - **Duration**: Typically completes in under 30 seconds
    - **Use Case**: First-line diagnostics for quick assessment

18. **Start-FullDiagnostics**
    - **Purpose**: Comprehensive diagnostic collection including system logs and services
    - **Functions Called**:
      - Get-SystemInformation
      - Get-CPUStatistics (10 samples)
      - Get-MemoryStatistics
      - Get-DiskStatistics
      - Get-NetworkStatistics
      - Get-TopProcesses (top 15)
      - Get-ServiceStatus
      - Get-EventLogErrors (48 hours, 100 events)
      - Get-WindowsUpdateStatus
      - Get-SecuritySoftwareStatus
      - Export-DiagnosticsReport
    - **Duration**: Typically 1-2 minutes depending on system
    - **Use Case**: Deep-dive analysis when quick snapshot insufficient

## Main Execution Flow

### Initialization Phase

1. **Requirements Check**: Script declares requirements (#Requires directives)
   - PowerShell 5.1 minimum
   - Administrator privileges mandatory
2. **Variable Setup**: Initializes global variables
3. **Directory Creation**: Creates output directory if not exists

### User Interface Loop

1. **Banner Display**: Shows application title and description
2. **Menu Loop**: While ($running)
   - Display main menu
   - Accept user input (1-9)
   - Execute corresponding function based on choice
   - Clear DiagnosticsData hashtable before new collection
   - Pause for user acknowledgment after completion
   - Return to menu (except on exit)

### Choice Execution Details

**Choice 1 - Quick Snapshot**:
- Resets DiagnosticsData
- Calls Start-QuickSnapshot
- Waits for key press

**Choice 2 - Extended Monitoring (30 min)**:
- Resets DiagnosticsData
- Collects system info
- Runs 30-minute monitoring (60-second intervals)
- Collects top 15 processes
- Exports report

**Choice 3 - Custom Extended Monitoring**:
- Prompts user for duration (minutes)
- Validates input is numeric
- Executes same as Choice 2 with custom duration
- Shows error if input invalid

**Choice 4 - Full Diagnostics**:
- Resets DiagnosticsData
- Calls Start-FullDiagnostics
- Collects all available diagnostic data

**Choice 5 - Network Diagnostics**:
- Collects system info and network statistics only
- Exports focused report

**Choice 6 - Disk Analysis**:
- Collects system info and disk statistics only
- Exports focused report

**Choice 7 - Process Analysis**:
- Collects system info and top 20 processes
- Exports focused report

**Choice 8 - View Previous Reports**:
- Lists all .zip files in output directory
- Shows file name, size, creation time
- Displays directory path

**Choice 9 - Exit**:
- Sets $running to $false
- Exits loop
- Displays goodbye message

## Data Structure

### DiagnosticsData Hashtable Keys

The script stores all collected data in a hashtable with the following structure:

```
$script:DiagnosticsData = @{
    SystemInformation = PSCustomObject { ... }
    CPUStatistics = PSCustomObject { ... }
    MemoryStatistics = PSCustomObject { ... }
    DiskStatistics = PSCustomObject { 
        Volumes = @(...)
        IOStatistics = @(...)
    }
    NetworkStatistics = PSCustomObject {
        Adapters = @(...)
        ConnectivityTest = @{ ... }
        ConnectionStats = @{ ... }
    }
    TopProcesses = PSCustomObject {
        TopCPUProcesses = @(...)
        TopMemoryProcesses = @(...)
        TotalProcessCount = int
    }
    ServiceStatus = PSCustomObject { ... }
    EventLogErrors = PSCustomObject {
        ErrorCount = int
        TimeRange = string
        Errors = @(...)
    }
    WindowsUpdateStatus = PSCustomObject { ... }
    SecuritySoftware = PSCustomObject { ... }
    ExtendedMonitoring = PSCustomObject {
        Samples = @(...)
        Statistics = @{ ... }
    }
}
```

### Output File Formats

**JSON Output**:
- Complete data structure serialized
- Depth: 10 levels
- Encoding: UTF-8
- Machine-readable for automated processing

**HTML Output**:
- Human-readable formatted report
- Embedded CSS for styling
- Responsive layout
- Color-coded warnings
- Tables for tabular data

**ZIP Archive**:
- Contains both JSON and HTML
- Compression level: Optimal
- Ready for email attachment or upload

## Error Handling Strategy

### Global Error Preference
- Set to "Continue" to allow script to proceed despite individual component failures
- Each function has localized try-catch blocks

### Function-Level Error Handling
- Each data collection function wrapped in try-catch
- Failures logged to console with color-coded messages
- Returns null on failure (graceful degradation)
- Script continues to collect other data even if one component fails

### User Notifications
- Success: Green messages with checkmark
- In Progress: Yellow messages with asterisk
- Errors: Red messages with exclamation mark
- Information: Cyan/White messages

## Performance Considerations

### Resource Usage

**CPU Impact**:
- Minimal during data collection
- CPU sampling uses 1-second intervals (non-blocking)
- Extended monitoring sleeps between samples

**Memory Impact**:
- Stores all samples in memory during extended monitoring
- Typical usage: <50 MB for 30-minute monitoring session

**Disk Impact**:
- Output files typically 100-500 KB (compressed)
- Uncompressed reports: 500 KB - 2 MB

### Execution Time

- Quick Snapshot: 15-30 seconds
- Full Diagnostics: 1-2 minutes
- Extended Monitoring: User-specified duration (default 30 minutes)

## Security Considerations

### Required Permissions
- Administrator privileges required for:
  - Performance counter access
  - Event log queries
  - Service enumeration
  - Windows Update status
  - Security software queries

### Data Sensitivity
- Contains system configuration details
- Includes running process information
- May contain service account names
- Does NOT collect: passwords, keys, personal data, file contents

### File Security
- Output files stored in user's TEMP directory
- Requires admin access to read output files
- Should be transmitted securely to support

## Extensibility

### Adding New Data Collection Functions

To add new diagnostic capabilities:

1. Create function following naming convention `Get-[Category]Statistics`
2. Add try-catch error handling
3. Store results in `$script:DiagnosticsData.[Category]`
4. Add console output with Write-ColorOutput
5. Return PSCustomObject with collected data

### Adding New Menu Options

To add menu options:

1. Update Show-MainMenu with new option number
2. Add new case in switch statement
3. Clear DiagnosticsData if needed
4. Call appropriate collection functions
5. Export report if needed

### Customizing HTML Output

The New-HTMLReport function can be extended to:
- Add new sections for new data types
- Modify styling/colors
- Add charts/graphs (requires JavaScript)
- Change threshold values for color coding

## Testing and Validation Checklist

When reviewing or verifying this script, check the following:

### Functionality Verification

- [ ] Script requires PowerShell 5.1 or later
- [ ] Script requires Administrator privileges
- [ ] All data collection functions handle errors gracefully
- [ ] Extended monitoring can be cancelled with Ctrl+C
- [ ] Output directory is created if missing
- [ ] All files are properly created (JSON, HTML, ZIP)
- [ ] ZIP archive contains both JSON and HTML files
- [ ] Progress indicators work correctly
- [ ] Menu loop continues until exit is selected
- [ ] Previous reports can be listed and located

### Data Collection Verification

- [ ] System information includes all specified fields
- [ ] CPU statistics collects multiple samples and calculates averages
- [ ] Memory statistics includes physical and committed memory
- [ ] Disk statistics covers all fixed volumes
- [ ] Network statistics includes active adapters only
- [ ] Process lists are sorted correctly (CPU and Memory)
- [ ] Service status identifies critical services
- [ ] Event log errors are filtered by severity and time
- [ ] Windows Update status checks registry keys
- [ ] Security software includes Defender and Firewall

### Extended Monitoring Verification

- [ ] Duration and interval parameters work correctly
- [ ] Samples are collected at specified intervals
- [ ] Progress updates every sample
- [ ] Statistics calculated correctly (min, max, avg)
- [ ] Timestamps are accurate
- [ ] All performance counters are accessible

### Report Generation Verification

- [ ] JSON file contains all collected data
- [ ] HTML file renders correctly in browsers
- [ ] Color coding works for thresholds
- [ ] Tables display data properly
- [ ] ZIP file can be extracted successfully
- [ ] File naming includes server name and timestamp

### User Experience Verification

- [ ] Menu is clear and easy to understand
- [ ] Color coding improves readability
- [ ] Progress indicators show accurate status
- [ ] Error messages are helpful
- [ ] Success messages confirm completion
- [ ] Upload instructions are clear

### Edge Case Handling

- [ ] Handles servers with no page file
- [ ] Handles servers with missing performance counters
- [ ] Handles event logs with no errors
- [ ] Handles servers with no network adapters
- [ ] Handles invalid user input in menu
- [ ] Handles insufficient permissions gracefully
- [ ] Handles disk space issues for output files

## Common Issues and Troubleshooting

### Issue: "Script cannot be loaded because running scripts is disabled"
- **Cause**: PowerShell execution policy
- **Solution**: Run `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

### Issue: "Access Denied" errors
- **Cause**: Not running as Administrator
- **Solution**: Right-click PowerShell, select "Run as Administrator"

### Issue: Performance counters return zero or null
- **Cause**: Performance counter corruption or service not running
- **Solution**: Rebuild performance counters with `lodctr /R`

### Issue: Extended monitoring terminates early
- **Cause**: Server reboot, session timeout, or Ctrl+C pressed
- **Solution**: Script handles gracefully and exports partial data

### Issue: HTML report doesn't display correctly
- **Cause**: Browser security settings or corrupted HTML
- **Solution**: Try different browser or check HTML file integrity

## Version History and Maintenance

### Current Version: 1.0

**Initial Release Features**:
- Interactive menu system
- Quick snapshot diagnostics
- Extended monitoring (default and custom duration)
- Full comprehensive diagnostics
- Specialized diagnostic modes (network, disk, process)
- JSON and HTML report generation
- Compressed archive creation
- Previous report viewing

### Future Enhancement Opportunities

- **Performance Graphs**: Add visual charts to HTML report using JavaScript
- **Email Integration**: Automatically email reports to support
- **Scheduled Execution**: Add support for Task Scheduler integration
- **Real-time Dashboard**: Live monitoring view with auto-refresh
- **Comparison Mode**: Compare two diagnostic reports
- **Alert Thresholds**: Configurable thresholds for automatic warnings
- **Export to CSV**: Additional export format for spreadsheet analysis
- **Database Logging**: Store historical data for trend analysis
- **Remote Execution**: Collect diagnostics from multiple servers
- **Configuration File**: External config for customizable settings

## Integration with Support Workflow

### Recommended Customer Instructions

1. Download the script to your VPS
2. Right-click PowerShell and select "Run as Administrator"
3. Navigate to script location
4. Run: `.\VPS-Diagnostics.ps1`
5. Select option 2 for extended monitoring (or option 1 for quick snapshot)
6. Wait for completion
7. Upload the generated ZIP file to your support ticket

### Support Team Benefits

- Standardized diagnostic data across all tickets
- Reduced back-and-forth communication
- Faster problem identification
- Historical data for trend analysis
- JSON format enables automated analysis
- HTML format provides quick visual assessment

## Compliance and Best Practices

### PowerShell Best Practices Followed

- Approved verb usage (Get-, Start-, Export-, Show-)
- Comment-based help for functions
- Proper parameter validation
- Error handling with try-catch
- Progress indicators for long operations
- Proper scope usage (script-scoped variables)
- Consistent code formatting
- Descriptive variable names

### Windows Server Best Practices

- Minimal system impact
- Non-destructive data collection
- No system modifications
- Respects existing security configurations
- Uses native Windows cmdlets and classes

## Conclusion

This script provides a comprehensive, user-friendly solution for collecting VPS performance diagnostics. It balances thoroughness with ease of use, making it suitable for both technical and non-technical customers. The modular design allows for easy extension and customization while maintaining stability and error resilience.

The script successfully addresses the original business problem by:
- Eliminating the need for customers to know what data to collect
- Standardizing diagnostic information across support tickets
- Reducing support resolution time
- Providing both machine-readable and human-readable outputs
- Creating a seamless workflow from collection to ticket submission