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
-   **Depth control via `MaxDepth`**
    -   `0` = root folder only\
    -   `1` = root + children\
    -   `2` = root + children + grandchildren\
    -   *(Press ENTER at prompt to scan unlimited depth)*
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

### **Basic Example**

``` powershell
.\FolderAclAudit.ps1 -RootPath "\\FS01\TrainingFolder"
```

When prompted for **MaxDepth**, press:

-   **ENTER** → unlimited depth\
-   **0** → only the root\
-   **1** → root + children\
-   **2** → root + children + grandchildren\
-   etc.

### **Custom Output Paths**

``` powershell
.\FolderAclAudit.ps1 `
  -RootPath "\\FS01\TrainingFolder" `
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

### **MaxDepth = Unlimited (ENTER)**

It scans every folder under the root.

------------------------------------------------------------------------

## ⚙️ Requirements

-   Windows 10/11 or Windows Server\
-   PowerShell 5+\
-   Read access to target folders\
-   Share-permission retrieval requires remote CIM access if scanning
    UNC paths

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

-   Full transcript written to the log file you specify\
-   Any unreadable folders produce entries in:\
    **`<csvfilename>.errors.csv`**

The audit **never stops** due to permission failures --- it logs and
continues.

------------------------------------------------------------------------

## 📄 License

Free to use, modify, and integrate into your environment.

------------------------------------------------------------------------

If you want a version with: - Effective permissions\
- Group nesting expansion\
- Risk scoring\
- Or HTML/Excel formatted reports

...I can generate those too.
