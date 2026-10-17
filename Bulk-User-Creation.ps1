<#
.SYNOPSIS
    Automated Bulk User Provisioning Script for corp.local

.DESCRIPTION
    Provisions departmental user accounts into the Corp_Company OU structure
    under the corp.local Active Directory domain. Each user is created in the
    appropriate departmental OU, assigned a secure temporary password, forced
    to change it at first logon, and added to the corresponding AGDLP security
    group. The script validates that target OUs exist before attempting any
    write operations and produces color-coded console output for audit trails.

.NOTES
    Domain  : corp.local
    Server  : DC-01 (192.168.67.10)
    Author  : Systems Administrator
    Requires: ActiveDirectory PowerShell module (RSAT)
#>

# ─────────────────────────────────────────────────────────────────────────────
# Module & Environment Prerequisites
# ─────────────────────────────────────────────────────────────────────────────
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "[INFO]  ActiveDirectory module loaded successfully." -ForegroundColor Cyan
}
catch {
    Write-Host "[FATAL] ActiveDirectory module is not available. Install RSAT or run on a Domain Controller." -ForegroundColor Red
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Domain Configuration
# ─────────────────────────────────────────────────────────────────────────────
$DomainDN     = "DC=corp,DC=local"
$DomainFQDN   = "corp.local"
$ParentOU     = "OU=Corp_Company,$DomainDN"

# ─────────────────────────────────────────────────────────────────────────────
# Secure Temporary Password (enforce change at first logon)
# ─────────────────────────────────────────────────────────────────────────────
$TempPassword = ConvertTo-SecureString "C0rp@Temp2026!" -AsPlainText -Force

# ─────────────────────────────────────────────────────────────────────────────
# User Dataset — Departmental Mapping
# ─────────────────────────────────────────────────────────────────────────────
$Users = @(
    # ── IT Department ──
    @{ FirstName = "Arun";    LastName = "Patel";   SamAccount = "apatel";   Department = "IT_Dept";      Title = "Systems Administrator";   SecurityGroup = "SG_IT_Users" }
    @{ FirstName = "Priya";   LastName = "Menon";   SamAccount = "pmenon";   Department = "IT_Dept";      Title = "Network Engineer";        SecurityGroup = "SG_IT_Users" }

    # ── HR Department ──
    @{ FirstName = "Rahul";   LastName = "Sharma";  SamAccount = "rsharma";  Department = "HR_Dept";      Title = "HR Analyst";              SecurityGroup = "SG_HR_Users" }
    @{ FirstName = "Sneha";   LastName = "Iyer";    SamAccount = "siyer";    Department = "HR_Dept";      Title = "Talent Acquisition Lead"; SecurityGroup = "SG_HR_Users" }

    # ── Finance Department ──
    @{ FirstName = "Suresh";  LastName = "Rao";     SamAccount = "srao";     Department = "Finance_Dept"; Title = "Financial Analyst";       SecurityGroup = "SG_Finance_Users" }
    @{ FirstName = "Ananya";  LastName = "Reddy";   SamAccount = "areddy";   Department = "Finance_Dept"; Title = "Accounts Payable Clerk";  SecurityGroup = "SG_Finance_Users" }
)

# ─────────────────────────────────────────────────────────────────────────────
# Counters
# ─────────────────────────────────────────────────────────────────────────────
$SuccessCount = 0
$SkipCount    = 0
$FailCount    = 0

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host "  BULK USER PROVISIONING — $DomainFQDN"                         -ForegroundColor White
Write-Host "  Target Root OU : $ParentOU"                                    -ForegroundColor DarkGray
Write-Host "  Timestamp      : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"   -ForegroundColor DarkGray
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# Validate Root OU Exists
# ─────────────────────────────────────────────────────────────────────────────
try {
    Get-ADOrganizationalUnit -Identity $ParentOU -ErrorAction Stop | Out-Null
    Write-Host "[OK]    Root OU verified: $ParentOU" -ForegroundColor Green
}
catch {
    Write-Host "[FATAL] Root OU '$ParentOU' does not exist. Aborting." -ForegroundColor Red
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Provision Each User
# ─────────────────────────────────────────────────────────────────────────────
foreach ($User in $Users) {

    $FullName   = "$($User.FirstName) $($User.LastName)"
    $UPN        = "$($User.SamAccount)@$DomainFQDN"
    $TargetOU   = "OU=$($User.Department),$ParentOU"

    Write-Host "───────────────────────────────────────────────────────────" -ForegroundColor DarkGray

    # ── Validate departmental OU ──
    try {
        Get-ADOrganizationalUnit -Identity $TargetOU -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Host "[SKIP]  OU not found: $TargetOU — skipping $FullName" -ForegroundColor Yellow
        $SkipCount++
        continue
    }

    # ── Check if user already exists ──
    $Existing = Get-ADUser -Filter "SamAccountName -eq '$($User.SamAccount)'" -ErrorAction SilentlyContinue
    if ($Existing) {
        Write-Host "[SKIP]  User '$($User.SamAccount)' already exists in AD — skipping." -ForegroundColor Yellow
        $SkipCount++
        continue
    }

    # ── Create user account ──
    try {
        New-ADUser `
            -Name                  $FullName `
            -GivenName             $User.FirstName `
            -Surname               $User.LastName `
            -DisplayName           $FullName `
            -SamAccountName        $User.SamAccount `
            -UserPrincipalName     $UPN `
            -Title                 $User.Title `
            -Department            $User.Department `
            -Path                  $TargetOU `
            -AccountPassword       $TempPassword `
            -Enabled               $true `
            -ChangePasswordAtLogon $true `
            -ErrorAction           Stop

        Write-Host "[CREATED] $FullName ($($User.SamAccount)) → $TargetOU" -ForegroundColor Green

        # ── Add user to departmental security group ──
        try {
            Add-ADGroupMember -Identity $User.SecurityGroup -Members $User.SamAccount -ErrorAction Stop
            Write-Host "[GROUP]   Added $($User.SamAccount) → $($User.SecurityGroup)" -ForegroundColor Cyan
        }
        catch {
            Write-Host "[WARN]  Could not add $($User.SamAccount) to $($User.SecurityGroup): $_" -ForegroundColor Yellow
        }

        $SuccessCount++
    }
    catch {
        Write-Host "[FAIL]  Error creating $FullName : $_" -ForegroundColor Red
        $FailCount++
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Summary Report
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host "  PROVISIONING COMPLETE"                                         -ForegroundColor White
Write-Host "  Created : $SuccessCount"                                       -ForegroundColor Green
Write-Host "  Skipped : $SkipCount"                                          -ForegroundColor Yellow
Write-Host "  Failed  : $FailCount"                                          -ForegroundColor Red
Write-Host "  Total   : $($Users.Count)"                                     -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host ""