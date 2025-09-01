# Please run with administrator privileges

# Create a WUA session
$updateSession = New-Object -ComObject Microsoft.Update.Session
$updateSession.ClientApplicationID = "WUA API Sample - Search, Download, Install and Restart if required"

Write-Host "Searching for updates..."
$updateSearcher = $updateSession.CreateUpdateSearcher()
$searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software'")
if ($searchResult.Updates.Count -eq 0) {
    Write-Host "No updates available for installation."
    return
}

# Collect updates to download
$updatesToDownload = New-Object -ComObject Microsoft.Update.UpdateColl
foreach ($update in $searchResult.Updates) {
    Write-Host "To be downloaded: $($update.Title)"
    $updatesToDownload.Add($update) | Out-Null
}

# Download updates
Write-Host "Downloading updates..."
$downloader = $updateSession.CreateUpdateDownloader()
$downloader.Updates = $updatesToDownload
$downloadResult = $downloader.Download()

# Collect updates to install
$updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
foreach ($update in $searchResult.Updates) {
    if ($update.IsDownloaded) {
        Write-Host "To be installed: $($update.Title)"
        $updatesToInstall.Add($update) | Out-Null
    }
}

# Install updates
if ($updatesToInstall.Count -gt 0) {
    Write-Host "Installing updates..."
    $installer = $updateSession.CreateUpdateInstaller()
    $installer.Updates = $updatesToInstall
    $installationResult = $installer.Install()

    Write-Host "Installation result code: $($installationResult.ResultCode)"

    # Check if a reboot is required
    if ($installationResult.RebootRequired) {
        $installer.Commit()
        Write-Host "A reboot is required. Restarting the system..."
        Restart-Computer -Force
    } else {
        Write-Host "No reboot is required."
    }
} else {
    Write-Host "No updates available for installation."
}