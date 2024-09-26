#!/bin/bash  
  
show_usage() {  
    echo "Usage: ./scriptName.sh --groupname <groupname> --filepath <filepath> --add || --remove"  
    exit 1  
}  
  
if [[ "$#" -lt 3 ]]; then  
    show_usage  
fi  
  
while [[ "$#" -gt 0 ]]; do  
    case $1 in  
        --groupname) groupname="$2"; shift ;;  
        --filepath) filepath="$2"; shift ;;  
        --add) action="add" ;;  
        --remove) action="remove" ;;  
        *) echo "Unknown parameter passed: $1"; show_usage ;;  
    esac  
    shift  
done  
  
if [[ -z "$groupname" || -z "$filepath" || -z "$action" ]]; then  
    show_usage  
fi  
  
# Define the log file path  
logfile="./add-remove-users.log"  
  
# Ensure the log file is created and writable  
touch "$logfile"  
exec > >(while read -r line; do echo "$(date '+%Y-%m-%d %H:%M:%S') $line"; done | tee -a "$logfile") 2>&1  
  
# Log the start of the script  
echo "Starting script"  
echo "Group Name: $groupname"  
echo "File Path: $filepath"  
echo "Action: $action"  
echo "Log File: $logfile"  
  
# Get the group ID from the group name  
group=$(az ad group list --filter "displayName eq '$groupname'" --query '[0].id' -o tsv)  
  
if [ -z "$group" ]; then  
    echo "Group not found."  
    exit 1  
fi  
  
echo "Group ID: $group"  
  
# Read email addresses from the file  
while IFS= read -r email  
do  
    # Get the user ID from the email  
    user=$(az ad user show --id "$email" --query 'id' -o tsv)  
      
    if [ -z "$user" ]; then  
        echo "User $email not found."  
        continue  
    fi  
  
    if [ "$action" == "add" ]; then  
        # Check if the user is already a member of the group  
        member_exists=$(az ad group member check --group "$group" --member-id "$user" --query 'value' -o tsv)  
          
        if [ "$member_exists" == "true" ]; then  
            echo "User $email with ID $user is already a member of $groupname."  
        else  
            # Add the user to the group  
            az ad group member add --group "$group" --member-id "$user"  
              
            # shellcheck disable=SC2181
            if [ $? -eq 0 ]; then  
                echo "Added $email with ID $user to $groupname."  
            else  
                echo "Failed to add $email with ID $user to $groupname."  
            fi  
        fi  
    elif [ "$action" == "remove" ]; then  
        # Check if the user is a member of the group  
        member_exists=$(az ad group member check --group "$group" --member-id "$user" --query 'value' -o tsv)  
          
        if [ "$member_exists" == "true" ]; then  
            # Remove the user from the group  
            az ad group member remove --group "$group" --member-id "$user"  
              
            # shellcheck disable=SC2181
            if [ $? -eq 0 ]; then  
                echo "Removed $email with ID $user from $groupname."  
            else  
                echo "Failed to remove $email with ID $user from $groupname."  
            fi  
        else  
            echo "User $email with ID $user is not a member of $groupname."  
        fi  
    fi  
done < "$filepath"  
  
# Log the end of the script  
echo "Script completed"  
echo "---------------------------------------"
