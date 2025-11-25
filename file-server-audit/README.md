# Folder ACL & Share Permission Audit Script

`FolderAclAudit.ps1` is a PowerShell auditing tool that extracts **NTFS
folder permissions** and **SMB share permissions** with optional
**depth‑limited scanning**.\
It outputs a clean CSV that includes IDs, inheritance flags, permission
levels, share access, and full ACL detail --- ideal for audits,
migrations, least‑privilege reviews, and security assessments.

------------------------------------------------------------------------

## 🔥 Key Features

-   **Folder-only auditing** (ignores files for speed & clarity)
-   **Depth control via `MaxDepth` parameter**
    -   Omit parameter or use empty string = unlimited depth\
    -   `0` = root folder only\
    -   `1` = root + children\
    -   `2` = root + children + grandchildren\
    -   Any positive integer for specific depth limit
-   **Streaming CSV output** (no large memory usage)
-   **NTFS ACL collection** including:
    -   Identity (user/group)
    -   Raw NTFS rights
    -   Simplified PermissionLevel (FullControl / Modify / Read / Other)
    -   Explicit vs Inherited permissions
    -   ACE order
-   **Share permission collection**
    -   Share name
    -   Server name
    -   Share local path
    -   Flattened summary of share rights
-   **Rich folder metadata**
    -   Parent folder
    -   Folder depth
    -   Owner
    -   Timestamps
-   **Logging + error output**\
    Transcript log + `.errors.csv` for any failed folder lookups.

------------------------------------------------------------------------

## 📄 CSV Output Columns

    ID
    Path
    ItemType
    ParentFolder
    FolderDepth
    ShareServer
    ShareName
    ShareLocalPath
    ShareAccessSummary
    ACEOrder
    ACEType
    Identity
    FileSystemRights
    PermissionLevel
    AccessControlType
    InheritanceFlags
    PropagationFlags
    IsInherited
    Owner
    LastWriteTime
    CreationTime

Each **ACE** (Access Control Entry) becomes **one row**.\
A folder with 10 AD groups = 10 rows in the CSV.

------------------------------------------------------------------------

## 🚀 How to Use

### **Interactive Mode (Recommended for First-Time Users)**

Simply run the script without parameters:

``` powershell
.\FolderAclAudit.ps1
```

The script will prompt you for:
1. **Root Path** - The folder path to audit (required)
2. **Max Depth** - How deep to scan (press ENTER for unlimited)

### **Command-Line Mode (All Parameters)**

``` powershell
.\FolderAclAudit.ps1 -RootPath "\\FS01\TrainingFolder"
```

By default, the script scans **all subfolders** (unlimited depth) when `-MaxDepth` is omitted.

### **Limited Depth Examples**

``` powershell
# Scan root folder only
.\FolderAclAudit.ps1 -RootPath "\\FS01\TrainingFolder" -MaxDepth "0"

# Scan root + first level children
.\FolderAclAudit.ps1 -RootPath "\\FS01\TrainingFolder" -MaxDepth "1"

# Scan root + children + grandchildren
.\FolderAclAudit.ps1 -RootPath "\\FS01\TrainingFolder" -MaxDepth "2"

# Explicitly set unlimited depth (same as omitting -MaxDepth)
.\FolderAclAudit.ps1 -RootPath "\\FS01\TrainingFolder" -MaxDepth ""
```

### **Custom Output Paths**

``` powershell
.\FolderAclAudit.ps1 `
  -RootPath "\\FS01\TrainingFolder" `
  -MaxDepth "2" `
  -OutputCsvPath "C:\Audit\Training_ACL.csv" `
  -LogFilePath "C:\Audit\Training_Log.txt"
```

### **Run without browsing the server**

UNC and local paths work:

-   `\\FS01\Share`\
-   `\\Domain\DFS\Namespace`\
-   `C:\LocalPath`

DFS works --- the script audits whichever backend target the path
resolves to.

------------------------------------------------------------------------

## 📌 Depth Behavior Explained

If your root is:

    \\FS01\TrainingFolder\

And you set:

### **MaxDepth = 1**

The script scans:

    TrainingFolder\         (depth 0)
    TrainingFolder\Dept1\   (depth 1)
    TrainingFolder\Dept2\   (depth 1)

It **does NOT** scan deeper subfolders.

### **MaxDepth = Unlimited (Omitted or Empty String)**

When you omit the `-MaxDepth` parameter or pass an empty string (`-MaxDepth ""`), it scans every folder under the root.

------------------------------------------------------------------------

## ⚙️ Requirements

-   Windows 10/11 or Windows Server\
-   PowerShell 5.1+ (Windows PowerShell) or PowerShell 7+ (PowerShell Core)\
-   Read access to target folders\
-   Share-permission retrieval requires remote CIM access if scanning UNC paths\
-   SMB share access for share permission collection

------------------------------------------------------------------------

## 🧪 Example CSV Snippet (based on typical GUI Security tab)

    ID,Path,Identity,FileSystemRights,PermissionLevel,ACEType
    1,\\FS01\Training\Videos,LTS.VIDEO.STAFF,"Modify, ReadAndExecute",Modify,Explicit
    2,\\FS01\Training\Videos,LTS.CAT.DOCS,"ReadAndExecute",Read,Explicit
    3,\\FS01\Training\Videos,MEDIA01.ADMINS.VIDEO,"FullControl",FullControl,Explicit

This matches what you see in the Windows Security tab but **adds share
perms and metadata GUI never shows**.

------------------------------------------------------------------------

## 📝 Logging & Error Handling

-   Full transcript written to the log file you specify (auto-generated if not provided)\
-   Any unreadable folders produce entries in:\
    **`<csvfilename>.errors.csv`**\
-   Progress indicators show current folder being processed\
-   Summary statistics displayed at completion (total ACE rows, errors encountered)

The audit **never stops** due to permission failures --- it logs and continues.

------------------------------------------------------------------------

## 📄 License

Free to use, modify, and integrate into your environment.

------------------------------------------------------------------------

## 📋 Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-RootPath` | Prompted if omitted | - | Root path to audit (UNC or local path) |
| `-MaxDepth` | Prompted if omitted | `""` (unlimited) | Maximum folder depth to scan (0 = root only) |
| `-OutputCsvPath` | No | Auto-generated | Path to output CSV file |
| `-LogFilePath` | No | Auto-generated | Path to log file |

**Note**: If `-RootPath` or `-MaxDepth` are not provided, the script will interactively prompt for them.

## 🔧 Advanced Usage

### **Local Path Example**

``` powershell
.\FolderAclAudit.ps1 -RootPath "C:\Data" -MaxDepth "1"
```

### **DFS Namespace Example**

``` powershell
.\FolderAclAudit.ps1 -RootPath "\\Domain\DFS\Namespace\Folder" -MaxDepth "3"
```

The script automatically detects and includes share information when available.

---

## 💡 Tips

-   For large directory trees, start with `-MaxDepth "1"` to test performance\
-   Output files are auto-named with timestamps if not specified\
-   CSV files use UTF-8 encoding for international character support\
-   Error CSV files are created only if errors occur during scanning
