using namespace System.Net;
using namespace System.IO;
using namespace System.Net.Sockets;
using namespace System;



# mapped folder inside vm
$vm_shared_folder = "C:\Users\$env:USERNAME\Sandbox\SandboxRun"

$vm_ip = Get-NetIPAddress | Where-Object AddressFamily -eq "IPv4" | Where-Object IPAddress -ne "127.0.0.1" | % { $_.IPAddress }
$vm_ip | Out-File "$vm_shared_folder\vm_ip" -Force

# config object for process 
$pinfo = New-Object System.Diagnostics.ProcessStartInfo
$pinfo.FileName = "powershell.exe"
$pinfo.RedirectStandardError = $true
$pinfo.RedirectStandardOutput = $true
$pinfo.UseShellExecute = $false
$pinfo.Arguments = "-executionpolicy bypass -file C:\Users\$env:USERNAME\Sandbox\SandboxRun\script.ps1"

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $pinfo

# start the server & process
[void]$process.Start()


# start server  
$addr = [IPEndpoint]::new([ipaddress]$vm_ip, 51877)
$socket = [Socket]::new([AddressFamily]::InterNetwork, [SocketType]::Stream, [ProtocolType]::Tcp)
$socket.Bind($addr)
$socket.Listen(1)
$connection = $socket.Accept()


[char[]]$send_buf = [char[]]::new(8)
[byte[]]$err_signal = 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF

while (!$process.StandardOutput.EndOfStream)
{
    for($i = 0; $i -lt $send_buf.Length; $i++) {$send_buf[$i] = 0}
    $recv_len = $process.StandardOutput.ReadBlock($send_buf, 0, 8)
    if (!$recv_len) {break}

    $null = $connection.Send($send_buf)
    [Console]::Write([Text.Encoding]::UTF8.GetString($send_buf))
}


$null = $connection.Send($err_signal)
$err_str = $process.StandardError.ReadToEnd()
$error_bytes = [Text.Encoding]::UTF8.GetBytes($err_str)
$null = $connection.Send($error_bytes)

Write-Host $err_str -ForegroundColor Red
$process.WaitForExit()

try
{
    $connection.Shutdown([SocketShutdown]::Both)
} 
finally 
{
    $connection.Close()
}



