# ====================================
# CONFIGURATION
# ====================================
# Liste des dossiers sources à surveiller
$Sources = @(
    "C:\Users\VotreNom\Documents\Projet1",
    "D:\Travail\Photos",
    "C:\Users\VotreNom\Bureau\DossierClient"
)
# Dossier racine de sauvegarde
$BackupRoot = "E:\Sauvegarde"
# Exclusions globales
$Exclusions = @("*.tmp", "*.bak", "node_modules", "bin", "obj", "Thumbs.db", "desktop.ini", ".DS_Store")
# Répertoire des logs
$logDir = "$env:USERPROFILE\Logs\SyncAuto"
# Délai avant synchronisation (en secondes)
$SyncDelay = 5
# Nombre maximum de tentatives
$MaxRetries = 3
# Intervalle de synchronisation forcée (en heures)
$ForceSyncInterval = 6

# Configuration des notifications Windows Toast
$EnableToastNotifications = $true
$AppId = "SyncAutoBackup"

# ====================================
# INITIALISATION
# ====================================
# Créer le répertoire de logs s'il n'existe pas
if (-not (Test-Path -Path $logDir)) {
    try {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        Write-Host "📁 Répertoire de logs créé : $logDir"
    }
    catch {
        Write-Host "❌ Erreur lors de la création du répertoire de logs : $_" -ForegroundColor Red
        exit 1
    }
}

# Vérifier l'existence des dossiers sources
foreach ($src in $Sources) {
    if (-not (Test-Path -Path $src)) {
        Write-Host "⚠️ Source non trouvée : $src" -ForegroundColor Yellow
    }
}

# Vérifier l'existence du dossier de sauvegarde
if (-not (Test-Path -Path $BackupRoot)) {
    try {
        New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
        Write-Host "📁 Dossier de sauvegarde créé : $BackupRoot"
    }
    catch {
        Write-Host "❌ Erreur lors de la création du dossier de sauvegarde : $_" -ForegroundColor Red
        exit 1
    }
}

# Dictionnaire de verrous pour éviter les doublons
$global:verrous = @{}
# Dictionnaire pour stocker les dernières synchronisations
$global:lastSyncs = @{}
# Dictionnaire pour stocker les compteurs de tentatives
$global:retryCount = @{}
# Dictionnaire pour stocker les derniers événements par dossier
$global:lastEventPerFolder = @{}
# Compteur d'erreurs pour les notifications
$global:errorCount = @{}

# ====================================
# FONCTIONS DE NOTIFICATION
# ====================================
function Show-ToastNotification {
    param (
        [string]$Title,
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Type = "Info"
    )
    
    if (-not $EnableToastNotifications) {
        return
    }
    
    # Déterminer l'icône en fonction du type
    $icon = switch ($Type) {
        "Info"    { "ℹ️" }
        "Warning" { "⚠️" }
        "Error"   { "❌" }
        "Success" { "✅" }
    }
    
    try {
        # Version pour Windows 10/11 (avec module BurntToast si disponible)
        if (Get-Command New-BurntToastNotification -ErrorAction SilentlyContinue) {
            $toastParams = @{
                Text = @("$icon $Title", $Message)
                AppLogo = $null
                Sound = 'Default'
            }
            New-BurntToastNotification @toastParams
        }
        else {
            # Solution de repli utilisant Windows.UI.Notifications
            $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
            $template = [Windows.UI.Notifications.ToastTemplateType]::ToastText02
            $toastXml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent($template)
            $toastTextElements = $toastXml.GetElementsByTagName("text")
            $toastTextElements[0].AppendChild($toastXml.CreateTextNode("$icon $Title")) > $null
            $toastTextElements[1].AppendChild($toastXml.CreateTextNode($Message)) > $null
            $toast = [Windows.UI.Notifications.ToastNotification]::new($toastXml)
            $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId)
            $notifier.Show($toast)
        }
    }
    catch {
        # Si les toast notifications échouent, utilisons la console
        Write-Host "$icon $Title - $Message" -ForegroundColor $(
            switch ($Type) {
                "Info"    { "White" }
                "Warning" { "Yellow" }
                "Error"   { "Red" }
                "Success" { "Green" }
            }
        )
    }
}

# ====================================
# JOURNALISATION
# ====================================
function Write-Log {
    param (
        [string]$Message,
        [string]$LogFile,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Ajouter au fichier journal
    Add-Content -Path $LogFile -Value $logMessage
    
    # Afficher dans la console avec couleur
    switch ($Level) {
        "INFO"    { Write-Host $logMessage -ForegroundColor Gray }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "ERROR"   { Write-Host $logMessage -ForegroundColor Red }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
    }
}

# ====================================
# SYNCHRONISATION
# ====================================
function Start-Sync {
    param (
        [string]$Source,
        [switch]$Force
    )
    
    # Vérifier si la source existe
    if (-not (Test-Path -Path $Source)) {
        return
    }
    
    $folderName = Split-Path $Source -Leaf
    $Destination = Join-Path -Path $BackupRoot -ChildPath $folderName
    $lockKey = "$Source→$Destination"
    $logFile = "$logDir\Sync_${folderName}_$(Get-Date -Format 'yyyyMMdd').log"
    
    # Vérifier si une synchronisation est déjà en cours
    if ($global:verrous[$lockKey]) {
        Write-Log -Message "Synchronisation déjà en cours pour $folderName, ignorée." -LogFile $logFile -Level "WARNING"
        return
    }
    
    # Vérifier si la dernière synchronisation est trop récente (sauf si forcée)
    if (-not $Force -and $global:lastSyncs[$lockKey]) {
        $timeSinceLastSync = (Get-Date) - $global:lastSyncs[$lockKey]
        if ($timeSinceLastSync.TotalSeconds -lt $SyncDelay) {
            return
        }
    }
    
    # Verrouiller la synchronisation
    $global:verrous[$lockKey] = $true
    
    try {
        # Créer le dossier de destination s'il n'existe pas
        if (-not (Test-Path $Destination)) {
            New-Item -Path $Destination -ItemType Directory -Force | Out-Null
        }
        
        # Préparer les options d'exclusion pour Robocopy
        $excludeOptions = @()
        foreach ($exclusion in $Exclusions) {
            if ($exclusion -like "*\*") {
                $excludeOptions += "/XD", $exclusion
            } else {
                $excludeOptions += "/XF", $exclusion
            }
        }
        
        # Paramètres Robocopy améliorés
        $robocopyParams = @(
            $Source,                # Source
            $Destination,           # Destination
            "/MIR",                 # Miroir (équivalent à /E /PURGE)
            "/Z",                   # Mode redémarrable
            "/FFT",                 # Utiliser des horodatages FAT (2 secondes de précision)
            "/XA:H",                # Exclure les fichiers cachés
            "/W:5",                 # Temps d'attente entre les tentatives
            "/R:3",                 # Nombre de tentatives
            "/NP",                  # Pas de pourcentage de progression
            "/MT:8",                # Multi-threaded (8 threads)
            "/TEE",                 # Afficher la sortie dans la console et le fichier journal
            "/BYTES",               # Afficher les tailles en octets
            "/TS",                  # Inclure les horodatages
            "/LOG+:$logFile"        # Journalisation
        ) + $excludeOptions
        
        Write-Log -Message "Début de la synchronisation de $Source vers $Destination" -LogFile $logFile -Level "INFO"
        
        # Exécuter Robocopy et récupérer le code de sortie de façon fiable
        $process = Start-Process -FilePath "robocopy" -ArgumentList $robocopyParams -NoNewWindow -Wait -PassThru
        $exitCode = $LASTEXITCODE
        
        # Analyser le code de retour de Robocopy
        switch ($exitCode) {
            0 { 
                Write-Log -Message "Synchronisation terminée. Aucun fichier copié." -LogFile $logFile -Level "SUCCESS"
                # Réinitialiser le compteur d'erreurs
                $global:errorCount[$lockKey] = 0
            }
            1 { 
                Write-Log -Message "Synchronisation terminée. Fichiers copiés avec succès." -LogFile $logFile -Level "SUCCESS"
                # Réinitialiser le compteur d'erreurs
                $global:errorCount[$lockKey] = 0
            }
            2 { 
                Write-Log -Message "Synchronisation terminée. Fichiers supplémentaires détectés." -LogFile $logFile -Level "SUCCESS"
                # Réinitialiser le compteur d'erreurs
                $global:errorCount[$lockKey] = 0
            }
            3 { 
                Write-Log -Message "Synchronisation terminée. Fichiers copiés et supplémentaires détectés." -LogFile $logFile -Level "SUCCESS"
                # Réinitialiser le compteur d'erreurs
                $global:errorCount[$lockKey] = 0
            }
            { $_ -ge 8 } { 
                Write-Log -Message "Échec de la synchronisation. Code de retour: $_" -LogFile $logFile -Level "ERROR"
                
                # Incrémenter le compteur d'erreurs
                if (-not $global:errorCount[$lockKey]) {
                    $global:errorCount[$lockKey] = 0
                }
                $global:errorCount[$lockKey]++
                
                # Gestion des tentatives
                if (-not $global:retryCount[$lockKey]) {
                    $global:retryCount[$lockKey] = 0
                }
                
                if ($global:retryCount[$lockKey] -lt $MaxRetries) {
                    $global:retryCount[$lockKey]++
                    Write-Log -Message "Nouvelle tentative ($($global:retryCount[$lockKey])/$MaxRetries) dans $SyncDelay secondes..." -LogFile $logFile -Level "WARNING"
                    
                    # Notification si on est à la moitié des tentatives
                    if ($global:retryCount[$lockKey] -eq [Math]::Ceiling($MaxRetries / 2)) {
                        Show-ToastNotification -Title "Problème de synchronisation" -Message "Difficultés avec la synchronisation de $folderName. Tentative $($global:retryCount[$lockKey])/$MaxRetries." -Type "Warning"
                    }
                    
                    # Libérer le verrou avant de réessayer
                    $global:verrous[$lockKey] = $false
                    Start-Sleep -Seconds $SyncDelay
                    Start-Sync -Source $Source -Force
                    return
                }
                else {
                    Write-Log -Message "Nombre maximum de tentatives atteint. Synchronisation abandonnée." -LogFile $logFile -Level "ERROR"
                    
                    # Afficher une notification
                    Show-ToastNotification -Title "Échec de la synchronisation" -Message "La synchronisation de $folderName a échoué après $MaxRetries tentatives." -Type "Error"
                    
                    $global:retryCount[$lockKey] = 0
                }
            }
            default { Write-Log -Message "Synchronisation terminée avec un code de retour: $_" -LogFile $logFile -Level "INFO" }
        }
        
        # Réinitialiser le compteur de tentatives en cas de succès
        $global:retryCount[$lockKey] = 0
        
        # Mettre à jour la dernière synchronisation
        $global:lastSyncs[$lockKey] = Get-Date
    }
    catch {
        Write-Log -Message "Erreur lors de la synchronisation: $_" -LogFile $logFile -Level "ERROR"
        
        # Notification d'erreur
        Show-ToastNotification -Title "Erreur de synchronisation" -Message "Erreur lors de la synchronisation de $folderName : $_" -Type "Error"
    }
    finally {
        # Libérer le verrou
        $global:verrous[$lockKey] = $false
    }
}

# ====================================
# GESTION DES ÉVÉNEMENTS
# ====================================
function Register-FolderWatcher {
    param (
        [string]$FolderPath
    )
    
    if (-not (Test-Path -Path $FolderPath)) {
        Write-Host "⚠️ Impossible de surveiller le dossier inexistant: $FolderPath" -ForegroundColor Yellow
        return
    }
    
    try {
        $folderName = Split-Path $FolderPath -Leaf
        Write-Host "🎯 Surveillance de: $FolderPath" -ForegroundColor Cyan
        
        $fsw = New-Object System.IO.FileSystemWatcher $FolderPath -Property @{
            IncludeSubdirectories = $true
            NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite, DirectoryName'
            EnableRaisingEvents = $true
        }
        
        # Action de synchronisation différée
        $action = {
            param($event)
            
            $sourcePath = $event.MessageData
            
            # Mémoriser l'événement par dossier
            $global:lastEventPerFolder[$sourcePath] = Get-Date
            
            # Délai avant synchronisation pour éviter les déclenchements multiples
            Start-Sleep -Seconds $using:SyncDelay
            
            # Vérifier si d'autres événements se sont produits entre-temps pour ce dossier spécifique
            $timeSinceLastEvent = (Get-Date) - $global:lastEventPerFolder[$sourcePath]
            if ($timeSinceLastEvent.TotalSeconds -ge $using:SyncDelay) {
                # Aucun événement récent pour ce dossier, procéder à la synchronisation
                & $using:syncScript $sourcePath
            }
        }
        
        # Script de synchronisation à exécuter
        $syncScript = {
            param($sourcePath)
            Start-Sync -Source $sourcePath
        }
        
        # Enregistrer les événements avec le chemin source comme données
        Register-ObjectEvent $fsw Changed -Action $action -MessageData $FolderPath | Out-Null
        Register-ObjectEvent $fsw Created -Action $action -MessageData $FolderPath | Out-Null
        Register-ObjectEvent $fsw Deleted -Action $action -MessageData $FolderPath | Out-Null
        Register-ObjectEvent $fsw Renamed -Action $action -MessageData $FolderPath | Out-Null
        
        # Effectuer une synchronisation initiale
        Start-Sync -Source $FolderPath -Force
    }
    catch {
        Write-Host "❌ Erreur lors de la configuration de la surveillance pour $FolderPath : $_" -ForegroundColor Red
    }
}

# ====================================
# SURVEILLANCE PLANIFIÉE
# ====================================
$timer = New-Object System.Timers.Timer
$timer.Interval = $ForceSyncInterval * 60 * 60 * 1000  # Conversion en millisecondes
$timer.AutoReset = $true
$timer.Enabled = $true

$timerAction = {
    foreach ($src in $using:Sources) {
        if (Test-Path -Path $src) {
            Write-Host "⏰ Synchronisation planifiée pour $src" -ForegroundColor Magenta
            Start-Sync -Source $src -Force
        }
    }
}

Register-ObjectEvent -InputObject $timer -EventName Elapsed -Action $timerAction | Out-Null

# ====================================
# DÉMARRAGE DE LA SURVEILLANCE
# ====================================
foreach ($src in $Sources) {
    Register-FolderWatcher -FolderPath $src
}

# ====================================
# MENU ET CONTRÔLE
# ====================================
Write-Host "`n📡 Surveillance active des dossiers. Contrôles disponibles:" -ForegroundColor Green
Write-Host "  • S - Synchronisation manuelle de tous les dossiers" -ForegroundColor Cyan
Write-Host "  • L - Afficher les journaux récents" -ForegroundColor Cyan
Write-Host "  • ? - Afficher l'aide" -ForegroundColor Cyan 
Write-Host "  • Q - Quitter le programme" -ForegroundColor Cyan
Write-Host ""

# Boucle principale
while ($true) {
    if ($host.UI.RawUI.KeyAvailable) {
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        
        switch ($key.Character) {
            "s" {
                Write-Host "`n🔄 Synchronisation manuelle de tous les dossiers..." -ForegroundColor Yellow
                foreach ($src in $Sources) {
                    if (Test-Path -Path $src) {
                        Start-Sync -Source $src -Force
                    }
                }
                Write-Host ""
            }
            "l" {
                Write-Host "`n📋 Affichage des dernières entrées de journal:" -ForegroundColor Yellow
                Get-ChildItem -Path $logDir -Filter "Sync_*_$(Get-Date -Format 'yyyyMMdd').log" | 
                ForEach-Object {
                    $logName = $_.Name
                    Write-Host "`n$logName" -ForegroundColor Cyan
                    Get-Content $_.FullName -Tail 10
                }
                Write-Host ""
            }
            "?" {
                Write-Host "`n❓ Aide:" -ForegroundColor Yellow
                Write-Host "  • S - Synchronisation manuelle de tous les dossiers" -ForegroundColor Cyan
                Write-Host "  • L - Afficher les journaux récents" -ForegroundColor Cyan
                Write-Host "  • ? - Afficher l'aide" -ForegroundColor Cyan
                Write-Host "  • Q - Quitter le programme" -ForegroundColor Cyan
                Write-Host ""
            }
            "q" {
                Write-Host "`n👋 Arrêt de la surveillance et sortie du programme..." -ForegroundColor Yellow
                # Nettoyer les événements enregistrés
                Get-EventSubscriber -Force | Unregister-Event -Force
                # Arrêter le timer
                $timer.Stop()
                $timer.Dispose()
                exit 0
            }
        }
    }
    
    Start-Sleep -Seconds 1
}
