# Azure AD Group Management Script  
  
This repository contains a Bash script to manage Azure Active Directory (AAD) group memberships. The script allows you to add or remove users from an AAD group based on a list provided in a file.  
  
## Prerequisites  
  
1. **Azure CLI:** Ensure Azure CLI is installed and configured on your machine or use Azure Cloud Shell.  
2. **Azure AD Permissions:** Ensure you have the necessary permissions to add or remove users from the AAD group.  
  
## Script Overview  
  
The script `add-remove-users.sh` performs the following operations:

- Adds users to an AAD group if they are not already members.  
- Removes users from an AAD group if they are currently members.  
- Logs each operation to a log file with timestamps.  
  
## Usage  
  
### Parameters  
  
- `--groupname` : The name of the AAD group.  
- `--filepath`  : The path to the file containing the list of user email addresses.  
- `--add`       : Adds users to the specified group.  
- `--remove`    : Removes users from the specified group.  
  
### Example Usage  
  
#### Users File Format

The file specified by --filepath should contain one email address per line. For example:

```bash
user1@example.com  
user2@example.com  
user3@example.com  
```

#### Make the script excutable first

`chmod +x ./add-remove-users.sh`

#### Adding Users to a Group  
  
```bash  
./add-remove-users.sh --groupname "Your Group Name" --filepath ./users.txt --add  
```

#### Removing Users from a Group

```bash  
./add-remove-users.sh --groupname "Your Group Name" --filepath ./users.txt --remove  
```

#### Log File

The script generates a log file named `add-remove-users.log` in the same directory where the script is run. The log file contains timestamps for each operation, indicating whether a user was added or removed successfully or if any errors occurred

#### Issues running the scripts

If you encounter the following error “Error from CloudShell - Failed to connect to MSI. Please make sure MSI is configured correctly.”

Try to run the following: `az login` and follow the instructions to login first
