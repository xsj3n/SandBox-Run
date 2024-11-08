# Sandbox-Run <filepath.ps1>using namespace System.Net;
using namespace System.IO;
using namespace System.Net.Sockets;
using namespace System.Net;
using namespace System;


param(
    [string]$ScriptPath 
)

function CheckErrorSignal() {
    param (
        [byte[]]$recv_buffer
    )

    $marked = 0
    [byte[]]$err_signal = 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
    for($i = 0; $i -lt $err_signal.Length; $i++) 
    {
        if ($err_signal[$i] -eq $recv_buffer[$i]) {$marked++}
    }

    if ($marked -eq 8) {return $false}
    return $true


    
}

$vm_script_path = "C:\Users\$env:USERNAME\Sandbox\SandboxRun\script.ps1"
$vm_shared_folder = "C:\Users\$env:USERNAME\Sandbox\SandboxRun"
if (!(Test-Path $vm_shared_folder))
{
    New-Item -ItemType Directory -Path $vm_shared_folder -Force
    Copy-Item .\vm_stream.ps1 -Destination "$vm_shared_folder\vm_stream.ps1" -Force
}

Copy-Item C:\Users\jredford\src\SandboxRun\vm_stream.ps1 -Destination "$vm_shared_folder\vm_stream.ps1" -Force
Copy-Item $ScriptPath -Destination $vm_script_path -Force

Remove-Item "$vm_shared_folder\vm_ip" -ErrorAction SilentlyContinue
Stop-Process -Name "WindowsSandbox" -Force -ErrorAction SilentlyContinue
Write-Host "[*] Starting VM" -ForegroundColor Green
$proc = Start-Process -FilePath "C:\Users\jredford\src\config.wsb" -PassThru # -->  powershell -executionpolicy unrestricted -command "start powershell {-noexit -file C:\Users\WDAGUtilityAccount\Sandbox\SandboxRun\vm_stream.ps1}"


Write-Host "[*] Awaiting VM IP..." -ForegroundColor Green
while (!(Test-Path "$vm_shared_folder\vm_ip" -ErrorAction SilentlyContinue)) 
{ 
    Start-Sleep -Milliseconds 500
}

$vm_ip = Get-Content "$vm_shared_folder\vm_ip"
if (!$vm_ip)
{
    Write-Host "[*] VM IP not found. Please retry..." -ForegroundColor Red
    $proc.Kill()
    exit 1
}
Write-Host "[*] VM IP: $vm_ip" -ForegroundColor Green


$socket = [Socket]::new([AddressFamily]::InterNetwork, [SocketType]::Stream, [ProtocolType]::Tcp)
$socket.Connect([IPEndpoint]::new([ipaddress]$vm_ip, 51877))

if (!$socket.Connected)
{
    Write-Host "[*] Unable to connect to the VM server" -ForegroundColor Red
}
Write-Host "[*] Connected to VM server" -ForegroundColor Green
Write-Host "[*] Script output on VM ==========================:`n" -ForegroundColor Green


[byte[]]$buffer = [byte[]]::new(8)
while($socket.Connected)
{
    for($i = 0; $i -lt $buffer.Length; $i++) {$buffer[$i] = 0}

    $recv_len = $socket.Receive($buffer, 0, 8, [SocketFlags]::None)
    if (!$recv_len) { break }

    if (CheckErrorSignal($buffer)) 
    {
        $str = [Text.Encoding]::UTF8.GetString($buffer, 0,  $recv_len) 
        [Console]::Write($str)
        continue 
    }

    $err_buf = [byte[]]$buffer = [byte[]]::new(4096)
    $recv_len = $socket.Receive($err_buf, 0, $err_buf.Length, [SocketFlags]::None)
    if (!$recv_len)
    {
        Write-Host "`n[!] VM script error output =========================:  None!" -ForegroundColor Green
        break
    }
    
    $str = [Text.Encoding]::UTF8.GetString($err_buf)
    Write-Host "`n[!] VM script error output =========================:`n" -ForegroundColor Yellow
    Write-Host $str -ForegroundColor Red
    
}

$proc.Kill()


























    # remove the script too early and it wont go
    #Start-Sleep -Seconds 20
    #Remove-Item $vm_script_path




# 