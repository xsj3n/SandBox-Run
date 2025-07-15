Write-Host "Downloading WebView2..."
$installer = "$home\Downloads\wv2.exe"
Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/p/?LinkId=2124703" -OutFile $installer
Write-Host "Installing WebView2..."
Start-Process -NoNewWindow -FilePath $installer -ArgumentList @("/silent", "/install") -Wait
Write-Host "Webview2 installed"