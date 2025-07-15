Write-Host "Downloading VCredist..."
$installer = "$home\Downloads\vc.exe"
Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" -OutFile $installer
Write-Host "Installing VCredist..."
Start-Process -NoNewWindow -FilePath $installer -ArgumentList @("/install" ,"/quiet" ,"/norestart") -Wait
Write-Host "VCredist installed"

