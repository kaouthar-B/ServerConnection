# Toujours dans PowerShell sur le serveur, vérifie :

# Test 1 : SSH est actif ?
Get-Service sshd
# → Doit afficher : Status = Running

# Test 2 : Pare-feu OK ?
Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" | Select-Object Enabled
# → Doit afficher : Enabled = True

# Test 3 : RDP actif ?
(Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server').fDenyTSConnections
# → Doit afficher : 0

# Test 4 : IP ?
ipconfig | findstr "IPv4"
# → Affiche ton IP fixe

Write-Host "Si tous les tests sont OK → tu peux debrancher le clavier !" -ForegroundColor Green