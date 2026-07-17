#This is a script I cobbled together to wean myself using AD tools to reset passwords.

[CmdletBinding()]
param (
    # Root of the search base (modify as necessary for your environment)
    [string]$SearchBase = "DC=yourdomain,DC=com",

    # Force the user to change their password at next logon
    [switch]$ForceChangeAtLogon,

    # Unlock the account after resetting the password
    [switch]$Unlock
)

if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Output "The ActiveDirectory module is not installed. Install RSAT / AD PowerShell tools and try again."
    exit 1
}
Import-Module ActiveDirectory -ErrorAction Stop

# Builds a consistent "First Last (username)" display string
function Get-UserSummary {
    param ($User)
    "$($User.GivenName) $($User.sn) ($($User.SamAccountName))"
}

# Function to select a user from a list
function Select-UserFromList {
    param (
        [array]$userList
    )

    # Display the user list with numbers
    Write-Output "Multiple users found:"
    for ($i = 0; $i -lt $userList.Count; $i++) {
        Write-Output "$($i + 1). $(Get-UserSummary $userList[$i])"
    }

    # Prompt for user selection
    $selection = Read-Host "Enter the number of the correct user"

    if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $userList.Count) {
        return $userList[[int]$selection - 1]
    } else {
        Write-Output "Invalid selection. Exiting."
        exit 1
    }
}

# Reset user password
$aduser = (Read-Host "Enter AD username").Trim()
if ([string]::IsNullOrWhiteSpace($aduser)) {
    Write-Output "No username entered. Exiting."
    exit 1
}

$checkuser = $null

Write-Output "Attempting to find user by SamAccountName: $aduser"

try {
    $checkuser = Get-ADUser -Filter {SamAccountName -eq $aduser} -Properties GivenName, sn -SearchBase $SearchBase -SearchScope Subtree -ErrorAction Stop
    if ($checkuser) {
        Write-Output "User exists in AD: $(Get-UserSummary $checkuser)"
    } else {
        Write-Output "User not found by username: $aduser."
    }
} catch {
    Write-Output "Error while searching for user by username: $_"
    exit 1
}

if (-not $checkuser) {
    # Prompt for the last name
    $lastname = (Read-Host "Enter AD user last name").Trim()
    if ([string]::IsNullOrWhiteSpace($lastname)) {
        Write-Output "No last name entered. Exiting."
        exit 1
    }

    # Find users by last name
    Write-Output "Searching for users with last name: $lastname"
    try {
        $users = Get-ADUser -Filter {sn -eq $lastname} -Properties GivenName, sn, SamAccountName -SearchBase $SearchBase -SearchScope Subtree -ErrorAction Stop
        Write-Output "Number of users found: $($users.Count)"

        if ($users.Count -gt 0) {
            # Display raw user information
            Write-Output "Raw user information:"
            $users | ForEach-Object { Write-Output "GivenName: $($_.GivenName), Surname: $($_.sn), SamAccountName: $($_.SamAccountName)" }
        } else {
            Write-Output "No users found with last name $lastname. Exiting."
            exit 1
        }

        if ($users.Count -eq 1) {
            $checkuser = $users[0]
            Write-Output "Single user found: $(Get-UserSummary $checkuser)"
        } else {
            # Multiple users found, prompt user to select one
            $checkuser = Select-UserFromList -userList $users
            Write-Output "User selected: $(Get-UserSummary $checkuser)"
        }
    } catch {
        Write-Output "Error while searching for users by last name: $_"
        exit 1
    }
}

if (-not $checkuser) {
    Write-Output "No valid user selected. Exiting."
    exit 1
}

if (-not $checkuser.Enabled) {
    Write-Output "Warning: account $($checkuser.SamAccountName) is currently disabled."
}

$confirm = Read-Host "Reset password for $(Get-UserSummary $checkuser)? (y/n)"
if ($confirm -notmatch '^[Yy]') {
    Write-Output "Cancelled."
    exit
}

# Prompt for new password
$password = Read-Host "Enter New User Password" -AsSecureString

# Set the new password
try {
    Set-ADAccountPassword -Identity $checkuser.SamAccountName -NewPassword $password -Reset -ErrorAction Stop
    Write-Output "Password has been reset."
} catch {
    Write-Output "Failed to reset password: $_"
    exit 1
}

if ($ForceChangeAtLogon) {
    try {
        Set-ADUser -Identity $checkuser.SamAccountName -ChangePasswordAtLogon $true -ErrorAction Stop
        Write-Output "User will be required to change their password at next logon."
    } catch {
        Write-Output "Failed to set change-password-at-logon flag: $_"
    }
}

if ($Unlock) {
    try {
        Unlock-ADAccount -Identity $checkuser.SamAccountName -ErrorAction Stop
        Write-Output "Account unlocked."
    } catch {
        Write-Output "Failed to unlock account: $_"
    }
}
