#This is a script I cobbled together to wean myself using AD tools to reset passwords.

# Function to select a user from a list
function Select-UserFromList {
    param (
        [array]$userList
    )

    # Display the user list with numbers
    Write-Output "Multiple users found:"
    for ($i = 0; $i -lt $userList.Count; $i++) {
        $user = $userList[$i]
        Write-Output "$($i + 1). $($user.GivenName) $($user.sn) ($($user.SamAccountName))"
    }

    # Prompt for user selection
    $selection = Read-Host "Enter the number of the correct user"

    if ($selection -match '^\d+$' -and $selection -le $userList.Count -and $selection -gt 0) {
        return $userList[$selection - 1]
    } else {
        Write-Output "Invalid selection. Exiting."
        exit
    }
}

# Set the root of the search base (modify as necessary for your environment)
$searchBase = "DC=yourdomain,DC=com"

# Reset user password
$aduser = Read-Host "Enter AD username"
$checkuser = $null

Write-Output "Attempting to find user by SamAccountName: $aduser"

try {
    $checkuser = Get-ADUser -Filter {SamAccountName -eq $aduser} -SearchBase $searchBase -SearchScope Subtree -ErrorAction Stop
    if ($checkuser) {
        Write-Output "User exists in AD: $($checkuser.GivenName) $($checkuser.sn) ($($checkuser.SamAccountName))"
    } else {
        Write-Output "User not found by username: $aduser."
    }
} catch {
    Write-Output "Error while searching for user by username: $_"
}

if (-not $checkuser) {
    # Prompt for the last name
    $lastname = Read-Host "Enter AD user last name"
    
    # Find users by last name
    Write-Output "Searching for users with last name: $lastname"
    try {
        $users = Get-ADUser -Filter {sn -eq $lastname} -Properties GivenName, sn, SamAccountName -SearchBase $searchBase -SearchScope Subtree -ErrorAction Stop
        Write-Output "Number of users found: $($users.Count)"

        if ($users.Count -gt 0) {
            # Display raw user information
            Write-Output "Raw user information:"
            $users | ForEach-Object { Write-Output "GivenName: $($_.GivenName), Surname: $($_.sn), SamAccountName: $($_.SamAccountName)" }
        } else {
            Write-Output "No users found with last name $lastname. Exiting."
            exit
        }

        if ($users.Count -eq 1) {
            $checkuser = $users[0]
            Write-Output "Single user found: $($checkuser.GivenName) $($checkuser.sn) ($($checkuser.SamAccountName))"
        } else {
            # Multiple users found, prompt user to select one
            $checkuser = Select-UserFromList -userList $users
            Write-Output "User selected: $($checkuser.GivenName) $($checkuser.sn) ($($checkuser.SamAccountName))"
        }
    } catch {
        Write-Output "Error while searching for users by last name: $_"
        exit
    }
}

if ($checkuser) {
    # Prompt for new password
    $password = Read-Host "Enter New User Password" -AsSecureString

    # Set the new password
    try {
        Set-ADAccountPassword -Identity $checkuser.SamAccountName -NewPassword $password -Reset
        Write-Output "Password has been reset."
    } catch {
        Write-Output "Failed to reset password: $_"
    }
} else {
    Write-Output "No valid user selected. Exiting."
}
