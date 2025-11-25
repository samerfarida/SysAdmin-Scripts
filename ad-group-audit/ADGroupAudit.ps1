# PSScriptAnalyzer suppressions - these warnings are acceptable for this interactive script
# .SYNOPSIS
#   AD Group Member Audit Script with interactive prompts
# .DESCRIPTION
#   This script audits Active Directory group members. Write-Host is intentionally used
#   for interactive user prompts and colored output, which is appropriate for this use case.
param(
    [Parameter(Mandatory = $false,
               HelpMessage = "Comma-separated list of AD group names (e.g. 'Group1,Group2,Group3')")]
    [string]$GroupNames,

    [Parameter(Mandatory = $false,
               HelpMessage = "Path to a text file containing group names (one per line)")]
    [string]$GroupNamesFile,

    [Parameter(Mandatory = $false,
               HelpMessage = "Path to output CSV file")]
    [string]$OutputCsvPath = $(Join-Path -Path (Get-Location) -ChildPath ("ADGroupAudit_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date))),

    [Parameter(Mandatory = $false,
               HelpMessage = "Path to log file")]
    [string]$LogFilePath = $(Join-Path -Path (Get-Location) -ChildPath ("ADGroupAudit_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date)))
)

# --- Interactive prompts for required parameters if not provided ---

if ([string]::IsNullOrWhiteSpace($GroupNames) -and [string]::IsNullOrWhiteSpace($GroupNamesFile)) {
    Write-Host ""
    Write-Host "=== AD Group Member Audit Script ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Please provide the group names:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  1. Enter comma-separated group names (e.g. 'Group1,Group2,Group3')" -ForegroundColor Gray
    Write-Host "  2. Enter a file path containing group names (one per line)" -ForegroundColor Gray
    Write-Host ""
    
    $userInput = Read-Host "Enter group names or file path"
    
    if ([string]::IsNullOrWhiteSpace($userInput)) {
        Write-Error "Group names or file path is required. Script cannot continue."
        exit 1
    }
    
    # Check if input is a file path
    if (Test-Path -LiteralPath $userInput -ErrorAction SilentlyContinue) {
        $GroupNamesFile = $userInput
        Write-Host "Using file path: $GroupNamesFile" -ForegroundColor Green
    } else {
        $GroupNames = $userInput
        Write-Host "Using comma-separated group names: $GroupNames" -ForegroundColor Green
    }
    Write-Host ""
}

# --- Core script starts here ---

# Start transcript logging
try {
    Start-Transcript -Path $LogFilePath -Append -ErrorAction Stop
} catch {
    Write-Warning "Failed to start transcript logging: $($_.Exception.Message)"
}

Write-Host "Starting AD Group Member audit..."
Write-Host "Output CSV    : $OutputCsvPath"
Write-Host "Log file      : $LogFilePath"
Write-Host "Start time    : $(Get-Date)"
Write-Host ""

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
}

# Check if ActiveDirectory module is available
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Log "ActiveDirectory module loaded successfully"
} catch {
    Write-Error "Failed to import ActiveDirectory module. Please ensure RSAT-AD-PowerShell is installed."
    Write-Log "Failed to import ActiveDirectory module: $($_.Exception.Message)" "ERROR"
    try {
        Stop-Transcript | Out-Null
    } catch {
        Write-Warning "Failed to stop transcript: $($_.Exception.Message)"
    }
    exit 1
}

# Collect group names from either parameter or file
$groupList = New-Object System.Collections.Generic.List[string]

if (-not [string]::IsNullOrWhiteSpace($GroupNamesFile)) {
    Write-Log "Reading group names from file: $GroupNamesFile"
    
    if (-not (Test-Path -LiteralPath $GroupNamesFile)) {
        Write-Error "File not found: $GroupNamesFile"
        Write-Log "File not found: $GroupNamesFile" "ERROR"
        try {
            Stop-Transcript | Out-Null
        } catch {
            Write-Warning "Failed to stop transcript: $($_.Exception.Message)"
        }
        exit 1
    }
    
    try {
        $fileContent = Get-Content -Path $GroupNamesFile -ErrorAction Stop
        foreach ($line in $fileContent) {
            $trimmedLine = $line.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmedLine)) {
                $groupList.Add($trimmedLine)
            }
        }
        Write-Log "Loaded $($groupList.Count) group names from file"
    } catch {
        Write-Error "Failed to read file: $($_.Exception.Message)"
        Write-Log "Failed to read file: $($_.Exception.Message)" "ERROR"
        try {
            Stop-Transcript | Out-Null
        } catch {
            Write-Warning "Failed to stop transcript: $($_.Exception.Message)"
        }
        exit 1
    }
} elseif (-not [string]::IsNullOrWhiteSpace($GroupNames)) {
    Write-Log "Parsing comma-separated group names"
    
    $groups = $GroupNames -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    
    foreach ($group in $groups) {
        $groupList.Add($group)
    }
    
    Write-Log "Loaded $($groupList.Count) group names from parameter"
} else {
    Write-Error "No group names provided. Please use -GroupNames or -GroupNamesFile parameter."
    Write-Log "No group names provided" "ERROR"
    try {
        Stop-Transcript | Out-Null
    } catch {
        Write-Warning "Failed to stop transcript: $($_.Exception.Message)"
    }
    exit 1
}

if ($groupList.Count -eq 0) {
    Write-Error "No valid group names found."
    Write-Log "No valid group names found" "ERROR"
    try {
        Stop-Transcript | Out-Null
    } catch {
        Write-Warning "Failed to stop transcript: $($_.Exception.Message)"
    }
    exit 1
}

Write-Log "Processing $($groupList.Count) group(s)..."

$errors = New-Object System.Collections.Generic.List[psobject]
$idCounter = 0
$script:CsvInitialized = $false

# Helper: write one row to CSV (streaming, header once)
function Write-UserRow {
    param(
        [pscustomobject]$Row,
        [string]$CsvPath
    )

    if (-not $script:CsvInitialized) {
        $Row | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
        $script:CsvInitialized = $true
    } else {
        $Row | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8 -Append
    }
}

# Process each group
$groupIndex = 0
foreach ($groupName in $groupList) {
    $groupIndex++
    Write-Progress -Activity "Auditing AD Groups" -Status "Processing group: $groupName ($groupIndex of $($groupList.Count))" -PercentComplete (($groupIndex / $groupList.Count) * 100)
    
    Write-Log "Processing group: $groupName"
    
    try {
        # Verify group exists
        $group = Get-ADGroup -Identity $groupName -ErrorAction Stop
        Write-Log "Found group: $groupName (DistinguishedName: $($group.DistinguishedName))"
        
        # Get all members of the group
        $members = Get-ADGroupMember -Identity $groupName -ErrorAction Stop
        
        if ($members.Count -eq 0) {
            Write-Log "Group '$groupName' has no members" "WARN"
            continue
        }
        
        Write-Log "Found $($members.Count) member(s) in group '$groupName'"
        
        # Process each member
        foreach ($member in $members) {
            try {
                # Check if member has SamAccountName (users do, groups/computers might not)
                $memberIdentity = $null
                if ($member.SamAccountName) {
                    $memberIdentity = $member.SamAccountName
                } elseif ($member.DistinguishedName) {
                    $memberIdentity = $member.DistinguishedName
                } else {
                    Write-Log "Member object has no identifiable attribute (SamAccountName or DN): $($member | ConvertTo-Json -Compress)" "WARN"
                    continue
                }
                
                # Get detailed user information
                $user = Get-ADUser -Identity $memberIdentity -Properties DisplayName, EmailAddress, UserPrincipalName, Enabled, Department, Title, Office, Manager, LastLogonDate, Created, Modified -ErrorAction Stop
                
                $idCounter++
                
                # Get manager name if available
                $managerName = $null
                if ($user.Manager) {
                    try {
                        $manager = Get-ADUser -Identity $user.Manager -Properties DisplayName -ErrorAction SilentlyContinue
                        if ($manager) {
                            $managerName = $manager.DisplayName
                        }
                    } catch {
                        # Manager lookup failed, leave as null
                    }
                }
                
                $row = [pscustomobject]@{
                    ID                = $idCounter
                    GroupName         = $groupName
                    GroupDN           = $group.DistinguishedName
                    SamAccountName    = $user.SamAccountName
                    DisplayName       = $user.DisplayName
                    UserPrincipalName = $user.UserPrincipalName
                    EmailAddress      = $user.EmailAddress
                    Enabled           = $user.Enabled
                    Department        = $user.Department
                    Title             = $user.Title
                    Office            = $user.Office
                    Manager           = $managerName
                    LastLogonDate     = $user.LastLogonDate
                    Created           = $user.Created
                    Modified          = $user.Modified
                    MemberDN          = $member.DistinguishedName
                    MemberObjectClass = if ($member.objectClass) { ($member.objectClass -join ',') } else { "User" }
                    AuditDate         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
                
                Write-UserRow -Row $row -CsvPath $OutputCsvPath
                
            } catch {
                # Member might not be a user (could be a group or computer)
                $memberSamAccount = if ($member.SamAccountName) { $member.SamAccountName } else { "N/A" }
                Write-Log "Member '$memberSamAccount' (ObjectClass: $($member.objectClass)) is not a user account or could not be retrieved: $($_.Exception.Message)" "WARN"
                
                # Still record the member even if we can't get full user details
                $idCounter++
                $row = [pscustomobject]@{
                    ID                = $idCounter
                    GroupName         = $groupName
                    GroupDN           = $group.DistinguishedName
                    SamAccountName    = $memberSamAccount
                    DisplayName       = $null
                    UserPrincipalName = $null
                    EmailAddress      = $null
                    Enabled           = $null
                    Department        = $null
                    Title             = $null
                    Office            = $null
                    Manager           = $null
                    LastLogonDate     = $null
                    Created           = $null
                    Modified          = $null
                    MemberDN          = if ($member.DistinguishedName) { $member.DistinguishedName } else { if ($member.Name) { $member.Name } else { "N/A" } }
                    MemberObjectClass = if ($member.objectClass) { ($member.objectClass -join ',') } else { "Unknown" }
                    AuditDate         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
                
                Write-UserRow -Row $row -CsvPath $OutputCsvPath
            }
        }
        
    } catch {
        $errObj = [pscustomobject]@{
            GroupName = $groupName
            Error     = $_.Exception.Message
            TimeStamp = Get-Date
        }
        $errors.Add($errObj) | Out-Null
        Write-Log "Failed to process group '$groupName': $($_.Exception.Message)" "ERROR"
    }
}

Write-Progress -Activity "Auditing AD Groups" -Completed

Write-Log "Finished collecting group members. CSV written to '$OutputCsvPath'"

if ($errors.Count -gt 0) {
    $errorCsvPath = [System.IO.Path]::ChangeExtension($OutputCsvPath, ".errors.csv")
    try {
        $errors | Export-Csv -Path $errorCsvPath -NoTypeInformation -Encoding UTF8
        Write-Log "Encountered $($errors.Count) errors. Details saved to '$errorCsvPath'" "WARN"
    } catch {
        Write-Log "Failed to export error details: $($_.Exception.Message)" "ERROR"
    }
} else {
    Write-Log "No errors encountered."
}

Write-Host ""
Write-Host "End time      : $(Get-Date)"
Write-Host "Total rows    : $idCounter"
Write-Host "Groups processed: $($groupList.Count)"
Write-Host "Audit complete."

try {
    Stop-Transcript | Out-Null
} catch {
    Write-Warning "Failed to stop transcript: $($_.Exception.Message)"
}

