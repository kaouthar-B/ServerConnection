# ╔════════════════════════════════════════════════════════════════╗
# ║  SCRIPT DE CONFIGURATION COMPLÈTE DU SERVEUR TOUR            ║
# ║  À exécuter UNE SEULE FOIS dans PowerShell Administrateur    ║
# ║  sur le serveur tour avec le clavier temporaire               ║
# ╚════════════════════════════════════════════════════════════════╝

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CONFIGURATION DU SERVEUR TOUR - DEBUT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ══════════════════════════════════════════════
# PARTIE 1 : INSTALLER ET ACTIVER SSH
# ══════════════════════════════════════════════
Write-Host "`n[1/8] Installation d'OpenSSH Server..." -ForegroundColor Yellow
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

Write-Host "[2/8] Demarrage du service SSH..." -ForegroundColor Yellow
Start-Service sshd

Write-Host "[3/8] Configuration du demarrage automatique SSH..." -ForegroundColor Yellow
Set-Service -Name sshd -StartupType 'Automatic'

# ══════════════════════════════════════════════
# PARTIE 2 : OUVRIR LE PARE-FEU POUR SSH
# ══════════════════════════════════════════════
Write-Host "[4/8] Configuration du pare-feu pour SSH (port 22)..." -ForegroundColor Yellow
if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' `
        -DisplayName 'OpenSSH Server (sshd)' `
        -Enabled True -Direction Inbound `
        -Protocol TCP -Action Allow -LocalPort 22
    Write-Host "   -> Regle pare-feu creee" -ForegroundColor Green
} else {
    Write-Host "   -> Regle pare-feu existe deja" -ForegroundColor Green
}

# ══════════════════════════════════════════════
# PARTIE 3 : ACTIVER LE BUREAU A DISTANCE (RDP)
# ══════════════════════════════════════════════
Write-Host "[5/8] Activation du Bureau a distance (RDP)..." -ForegroundColor Yellow
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
    -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
Write-Host "   -> RDP active" -ForegroundColor Green

# ══════════════════════════════════════════════
# PARTIE 4 : CONFIGURER UNE IP FIXE
# ══════════════════════════════════════════════
Write-Host "[6/8] Configuration de l'adresse IP..." -ForegroundColor Yellow

# D'abord, afficher l'interface reseau active
$activeAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
$currentIP = Get-NetIPAddress -InterfaceIndex $activeAdapter.ifIndex -AddressFamily IPv4 |
    Where-Object { $_.PrefixOrigin -ne "WellKnown" } | Select-Object -First 1
$gateway = (Get-NetRoute -InterfaceIndex $activeAdapter.ifIndex -DestinationPrefix "0.0.0.0/0" |
    Select-Object -First 1).NextHop

Write-Host "   Interface reseau : $($activeAdapter.Name)" -ForegroundColor White
Write-Host "   IP actuelle      : $($currentIP.IPAddress)" -ForegroundColor White
Write-Host "   Passerelle       : $gateway" -ForegroundColor White
Write-Host ""
Write-Host "   IMPORTANT : Notez ces informations !" -ForegroundColor Red
Write-Host "   L'IP actuelle sera fixee pour ne plus changer." -ForegroundColor Red
Write-Host ""

# Fixer l'IP actuelle (pour qu'elle ne change plus avec DHCP)
$confirm = Read-Host "   Voulez-vous fixer l'IP $($currentIP.IPAddress) ? (O/N)"
if ($confirm -eq "O" -or $confirm -eq "o") {
    # Supprimer la config DHCP actuelle
    Remove-NetIPAddress -InterfaceIndex $activeAdapter.ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetRoute -InterfaceIndex $activeAdapter.ifIndex -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue

    # Configurer l'IP fixe
    New-NetIPAddress `
        -InterfaceIndex $activeAdapter.ifIndex `
        -IPAddress $currentIP.IPAddress `
        -PrefixLength $currentIP.PrefixLength `
        -DefaultGateway $gateway

    # Configurer le DNS (Google DNS)
    Set-DnsClientServerAddress `
        -InterfaceIndex $activeAdapter.ifIndex `
        -ServerAddresses 8.8.8.8, 8.8.4.4

    Write-Host "   -> IP fixee : $($currentIP.IPAddress)" -ForegroundColor Green
} else {
    Write-Host "   -> IP non fixee (DHCP conserve)" -ForegroundColor Yellow
    Write-Host "   -> ATTENTION : l'IP peut changer apres un redemarrage !" -ForegroundColor Red
}

# ══════════════════════════════════════════════
# PARTIE 5 : DESACTIVER LA VEILLE ET L'ECRAN DE VERROUILLAGE
# ══════════════════════════════════════════════
Write-Host "[7/8] Desactivation de la mise en veille..." -ForegroundColor Yellow

# Desactiver la mise en veille (le serveur doit rester allume 24/7)
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
powercfg /change monitor-timeout-ac 0

# Desactiver le verrouillage automatique de l'ecran
# (pour que RDP puisse se connecter sans probleme)
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' `
    -Name "NoLockScreen" -Value 1 -Force -ErrorAction SilentlyContinue
New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' `
    -Force -ErrorAction SilentlyContinue | Out-Null
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' `
    -Name "NoLockScreen" -Value 1 -Force

Write-Host "   -> Mise en veille et verrouillage desactives" -ForegroundColor Green

# ══════════════════════════════════════════════
# PARTIE 6 : INSTALLER MINICONDA + ENVIRONNEMENT PYTHON
# ══════════════════════════════════════════════
Write-Host "[8/8] Installation de Miniconda et de l'environnement Python..." -ForegroundColor Yellow

$condaInstaller = "$env:TEMP\miniconda.exe"
if (!(Test-Path "C:\Users\$env:USERNAME\miniconda3\condabin\conda.bat")) {
    Write-Host "   Telechargement de Miniconda (peut prendre quelques minutes)..." -ForegroundColor White
    Invoke-WebRequest `
        -Uri "https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe" `
        -OutFile $condaInstaller
    Start-Process -Wait -FilePath $condaInstaller `
        -ArgumentList "/InstallationType=JustMe /RegisterPython=1 /S /D=C:\Users\$env:USERNAME\miniconda3"
    Remove-Item $condaInstaller -Force
    Write-Host "   -> Miniconda installe" -ForegroundColor Green
} else {
    Write-Host "   -> Miniconda deja installe" -ForegroundColor Green
}

# ══════════════════════════════════════════════
# RÉSUMÉ FINAL
# ══════════════════════════════════════════════
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CONFIGURATION TERMINEE AVEC SUCCES !" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Recuperer l'IP finale
$finalIP = (Get-NetIPAddress -InterfaceIndex $activeAdapter.ifIndex -AddressFamily IPv4 |
    Where-Object { $_.PrefixOrigin -ne "WellKnown" } | Select-Object -First 1).IPAddress
$username = $env:USERNAME

Write-Host "  INFORMATIONS A NOTER (TRES IMPORTANT) :" -ForegroundColor Red
Write-Host "  =========================================" -ForegroundColor Red
Write-Host ""
Write-Host "  Adresse IP du serveur  : $finalIP" -ForegroundColor White
Write-Host "  Nom d'utilisateur      : $username" -ForegroundColor White
Write-Host "  Port SSH               : 22" -ForegroundColor White
Write-Host "  Port RDP               : 3389" -ForegroundColor White
Write-Host ""
Write-Host "  COMMANDES A TAPER SUR TON PC :" -ForegroundColor Yellow
Write-Host "  ───────────────────────────────" -ForegroundColor Yellow
Write-Host "  Connexion SSH   : ssh $username@$finalIP" -ForegroundColor White
Write-Host "  Bureau a dist.  : mstsc /v:$finalIP" -ForegroundColor White
Write-Host ""
Write-Host "  Tu peux maintenant DEBRANCHER le clavier et la souris." -ForegroundColor Green
Write-Host "  Tout se fera a distance desormais !" -ForegroundColor Green
Write-Host ""