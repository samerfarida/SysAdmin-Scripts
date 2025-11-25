# AD Group Member Audit Script

`ADGroupAudit.ps1` is a PowerShell auditing tool that extracts **Active Directory group membership** information.\
It outputs a clean CSV that includes user details such as names, emails, usernames, and other relevant attributes --- ideal for audits, compliance reviews, and security assessments.

------------------------------------------------------------------------

## 🔥 Key Features

-   **Flexible input methods**
    -   Comma-separated group names via parameter or prompt
    -   File-based input (one group name per line)
-   **Comprehensive user information** including:
    -   Username (SamAccountName)
    -   Display Name
    -   Email Address
    -   User Principal Name (UPN)
    -   Account status (Enabled/Disabled)
    -   Department, Title, Office
    -   Manager information
    -   Last logon date
    -   Account creation and modification dates
-   **Group information** including:
    -   Group name
    -   Group Distinguished Name (DN)
-   **Member details** including:
    -   Member Distinguished Name
    -   Object class (User, Group, Computer, etc.)
-   **Streaming CSV output** (no large memory usage)
-   **Logging + error output**\
    Transcript log + `.errors.csv` for any failed group lookups.

------------------------------------------------------------------------

## 📄 CSV Output Columns

    ID
    GroupName
    GroupDN
    SamAccountName
    DisplayName
    UserPrincipalName
    EmailAddress
    Enabled
    Department
    Title
    Office
    Manager
    LastLogonDate
    Created
    Modified
    MemberDN
    MemberObjectClass
    AuditDate

Each **group member** becomes **one row**.\
A group with 50 users = 50 rows in the CSV.

------------------------------------------------------------------------

## 🚀 How to Use

### **Interactive Mode (Recommended for First-Time Users)**

Simply run the script without parameters:

``` powershell
.\ADGroupAudit.ps1
```

The script will prompt you for:
1. **Group Names** - Either comma-separated group names or a file path containing group names (one per line)

### **Command-Line Mode (Comma-Separated Groups)**

``` powershell
.\ADGroupAudit.ps1 -GroupNames "Domain Admins,Enterprise Admins,IT Staff"
```

### **Command-Line Mode (File Input)**

``` powershell
.\ADGroupAudit.ps1 -GroupNamesFile "C:\Groups\group-list.txt"
```

Example `group-list.txt` file:
```
Domain Admins
Enterprise Admins
IT Staff
Sales Team
Marketing Team
```

### **Custom Output Paths**

``` powershell
.\ADGroupAudit.ps1 `
  -GroupNames "Domain Admins,Enterprise Admins" `
  -OutputCsvPath "C:\Audit\AD_Groups_$(Get-Date -Format 'yyyyMMdd').csv" `
  -LogFilePath "C:\Audit\AD_Groups_$(Get-Date -Format 'yyyyMMdd').log"
```

### **Combined Example**

``` powershell
.\ADGroupAudit.ps1 `
  -GroupNamesFile ".\groups.txt" `
  -OutputCsvPath ".\audit_results.csv" `
  -LogFilePath ".\audit.log"
```

------------------------------------------------------------------------

## ⚙️ Requirements

-   Windows 10/11 or Windows Server
-   PowerShell 5.1+ (Windows PowerShell) or PowerShell 7+ (PowerShell Core)
-   **RSAT-AD-PowerShell** module installed (ActiveDirectory PowerShell module)
-   Appropriate AD permissions to read group membership and user attributes
-   Must be run on a domain-joined machine or with appropriate domain connectivity

### **Installing RSAT-AD-PowerShell**

On Windows 10/11:
```powershell
# Via PowerShell (as Administrator)
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
```

On Windows Server:
```powershell
# Install via Server Manager or PowerShell
Install-WindowsFeature RSAT-AD-PowerShell
```

------------------------------------------------------------------------

## 🧪 Example CSV Snippet

    ID,GroupName,SamAccountName,DisplayName,EmailAddress,Enabled,Department,Title
    1,Domain Admins,jdoe,John Doe,john.doe@company.com,True,IT,Systems Administrator
    2,Domain Admins,jsmith,Jane Smith,jane.smith@company.com,True,IT,Network Engineer
    3,IT Staff,jdoe,John Doe,john.doe@company.com,True,IT,Systems Administrator
    4,IT Staff,bwilliams,Bob Williams,bob.williams@company.com,True,IT,Help Desk Technician

This provides a clear view of group membership with all relevant user details.

------------------------------------------------------------------------

## 📝 Logging & Error Handling

-   Full transcript written to the log file you specify (auto-generated if not provided)
-   Any unreadable groups or members produce entries in:\
    **`<csvfilename>.errors.csv`**
-   Progress indicators show current group being processed
-   Summary statistics displayed at completion (total rows, groups processed, errors encountered)

The audit **never stops** due to permission failures --- it logs and continues.

### **Error Handling**

-   **Non-existent groups**: Logged as errors and recorded in `.errors.csv`
-   **Non-user members**: Groups or computers that are members are still recorded but with limited user details
-   **Permission issues**: Logged as errors and recorded in `.errors.csv`
-   **Missing attributes**: Null values are used for missing user attributes

------------------------------------------------------------------------

## 📋 Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-GroupNames` | No* | - | Comma-separated list of AD group names |
| `-GroupNamesFile` | No* | - | Path to a text file containing group names (one per line) |
| `-OutputCsvPath` | No | Auto-generated | Path to output CSV file |
| `-LogFilePath` | No | Auto-generated | Path to log file |

**Note**: Either `-GroupNames` or `-GroupNamesFile` must be provided. If neither is provided, the script will interactively prompt for input.

## 🔧 Advanced Usage

### **Using with PowerShell Pipeline**

``` powershell
# Get groups from another command
Get-ADGroup -Filter "Name -like 'IT*'" | Select-Object -ExpandProperty Name | Out-File groups.txt
.\ADGroupAudit.ps1 -GroupNamesFile "groups.txt"
```

### **Scheduled Task Example**

``` powershell
# Create a scheduled task to run weekly
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\Scripts\ADGroupAudit.ps1 -GroupNamesFile C:\Scripts\groups.txt"
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 2am
Register-ScheduledTask -TaskName "AD Group Audit" -Action $action -Trigger $trigger
```

### **Filtering Results**

After running the script, you can filter the CSV results:

``` powershell
# Import and filter disabled accounts
$results = Import-Csv "ADGroupAudit_20240101_120000.csv"
$disabled = $results | Where-Object { $_.Enabled -eq "False" }
$disabled | Export-Csv "disabled_accounts.csv" -NoTypeInformation

# Find users in multiple groups
$results | Group-Object SamAccountName | Where-Object { $_.Count -gt 1 } | Select-Object Name, Count
```

------------------------------------------------------------------------

## 💡 Tips

-   For large groups (1000+ members), the script may take some time to process
-   Output files are auto-named with timestamps if not specified
-   CSV files use UTF-8 encoding for international character support
-   Error CSV files are created only if errors occur during processing
-   The script handles nested groups (groups within groups) by showing the group as a member with its object class
-   Use file input for auditing many groups at once
-   Combine with other PowerShell commands to create comprehensive audit reports

------------------------------------------------------------------------

## 📄 License

Free to use, modify, and integrate into your environment.

