param(
    [String]$ScriptPath,
    [String[]]$ScriptList,
    [String]$ScriptParameters,
    [Parameter()]
    [ValidateSet("VCRedis", "WebView2")]
    [String[]]$Depends,
    [Parameter()]
    [ValidateSet("VSCode")]
    [String[]]$Packages,
    [switch]$WhatIf
)

# returns true if a script contains parameters
function Invoke-ParameterCheck {
    param ([String]$ScriptPath)
        $ast_errors = @()
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Convert-Path $ScriptPath), [ref]$null, [ref]$ast_errors)
        if ($null -eq $ast.ParamBlock) {
            return $true 
        }
        return $false
    
}


# Gets all the contents of a script below the paramblock 
function Get-ScriptParamsTruncated {
    param(
        [String]$ScriptPath,
        [Int]$ParametersEndOffset
    )

    return (Get-Content -Raw $ScriptPath).Substring($ParametersEndOffset)
}

if (!$PSBoundParameters.Count) {
    Write-Error "No arguements provided."
    exit 1
}

if ($ScriptPath -and $ScriptList) {
    Write-Error "Input either a single script path, or a list of script paths to run, not both."
    exit 1
}

$sandbox_dir = "C:\Users\WDAGUtilityAccount\SandboxShare" # sandbox_dir is the mapped folder path within the vm
$tmp_dir = "$home\AppData\Local\Temp\SandBoxShare"        # tmp_dir is the mapped folder path of the host 
$tmp_script_path = "$tmp_dir\run.ps1"   
if (!(Test-Path $tmp_dir)) {
    New-Item -ItemType Directory -Path $tmp_dir -Verbose
}



# remove cached wsb/ps1
Remove-Item -Path $tmp_script_path -ErrorAction SilentlyContinue
Remove-Item -Path "$tmp_dir\run.wsb" -ErrorAction SilentlyContinue

# we dont want to spend 10 years opening the sandbox if its gonna fail anyways 
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# we will build a new script file, injecting the code required to install deps into it 
# this will hold all of the scripts that are glued together
# this buffer will hold the "body" contents of all scripts 
$tmp_script_contents = @()
$whatif_action_buffer = @()

# if we have a list of scripts to run in sequence, then we loop through them, collecting the parameters and body content for each script into buffers
# after iterating through, add all collected parameters to the master script which will run on the vm, and add all of the body contents from each script into the master script 
if ($ScriptList) {
    $all_params = @()
    $ast_errors = @()  # TODO: chk for errors
    for ($i = 0; $i -lt $ScriptList.Length; $i++) {

        # we parse each script, saving its parameters & the contents seperately 
        $script_file = Get-Item $ScriptList[$i]
        if ($script_file.Length -eq 0) {
            Write-Error "An empty powershell file was passed in: $($script_file.Name)"
            exit 2
        }
        
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script_file.FullName, [ref]$null, [ref]$ast_errors)
        if ($ast.ParamBlock) {
            $all_params = $all_params + $ast.ParamBlock.Parameters
            $tmp_script_contents += (Get-ScriptParamsTruncated -ScriptPath $script_file.FullName -ParametersEndOffset $ast.ParamBlock.Extent.EndOffset) + "`n"
        } else {
           $tmp_script_contents += +"`n" + (Get-Content -Raw $script_file.FullName) + "`n"
        }
        
    }
     
    # join the "body" contents of all the scripts together 
    $tmp_script_contents = $tmp_script_contents -join "`n"
   

    # deduplicate collective parameters and then reconstruct them into a string
    $all_params_text = $all_params | Sort-Object { $_.Name.VariablePath.UserPath } -Unique | ForEach-Object {$_.Extent.Text}
    $combined_paramblock_text =  "param(`n  " + $($all_params_text[0..$($all_params_text.Length - 1)] -join ",`n  ") + "`n)"

    # output the reconstructed collective parameters 
    $combined_paramblock_text > $tmp_script_path
}

# this is just like what we do for $ScriptList above, but without the iteration because there is only one file
# in the future, it may be wise to conslidate the $ScriptPath flag's functionaility under $ScriptList
if ($ScriptPath) {
    $ast_errors = @()
    $script_file_path = Convert-Path $ScriptPath
    $script_file_ast = [System.Management.Automation.Language.Parser]::ParseFile($script_file_path, [ref]$null, [ref]$ast_errors)
    
    # get the "body" contents of the script & save it to
    $tmp_script_contents += Get-ScriptParamsTruncated -ScriptPath $script_file_path -ParametersEndOffset $script_file_ast.ParamBlock.Extent.EndOffset

    # add the comments and param block to the composite script using indexes from the ast
    (Get-Content -Raw $script_file_path).Substring(0, $script_file_ast.ParamBlock.Extent.EndOffset) > $tmp_script_path   
}



# disable progress bar in the master vm script
"`$ProgressPreference = 'SilentlyContinue'" >> $tmp_script_path

# Copy in dependencies required 
if ($Depends -contains "WebView2") {
    Get-Content -Raw "$PSScriptRoot\SandboxDependencies\sandbox_webview2.ps1" >> $tmp_script_path    
}
if ($Depends -contains "VCRedis") {
    Get-Content -Raw "$PSScriptRoot\SandboxDependencies\sandbox_vcredist.ps1" >> $tmp_script_path
}

# vscode  & create the required dirs for a portable install, if not found and the user specifies it 
if ($Packages -contains "VSCode" -and !(Test-Path "$tmp_dir\vscode\Code.exe")) {
    Remove-Item -Path "$tmp_dir\vscode" -Recurse -Force 
    if (!$WhatIf) {
        Write-Host "[*] Downloading VSCode..."
        Invoke-WebRequest -UseBasicParsing -Uri "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-archive" -OutFile "$tmp_dir\code.zip"
        Expand-Archive -Path "$tmp_dir\code.zip" -DestinationPath "$tmp_dir\vscode"  -Force
        Remove-Item -Path "$tmp_dir\code.zip" | Out-Null
        New-Item -Path "$tmp_dir\vscode\data" -ItemType Directory | Out-Null
        New-Item -Path "$tmp_dir\vscode\tmp" -ItemType Directory | Out-Null
    } else {
        $whatif_action_buffer += "[*] Download VSCode portable to folder: $tmp_dir"
        $whatif_action_buffer += "[*] Unzip the file containing the binary into $tmp_dir"
        $whatif_action_buffer += "[*] Setup the directories to enable portable mode for VSCode"
        $whatif_action_buffer += "[*] Remove zip file containing the VSCode portable binary"
    }
} 

# Code to create a lnk on the desktop of the vm, if the user set the flag for VSCode
if ($Packages -contains "VSCode") {
    @"
Write-Host "Creating VSCode lnk..."
`$WshShell = New-Object -ComObject WScript.Shell
`$Shortcut = `$WshShell.CreateShortcut("C:\ProgramData\Microsoft\Windows\Start Menu\Programs\VSCode.lnk")
`$Shortcut.TargetPath = "$sandbox_dir\vscode\Code.exe"
`$Shortcut.Save()
"@ >> $tmp_script_path
}

# if a script was specified, add it to them master script 
if ($ScriptPath -or $ScriptList) {
    # sometimes the target script(s) to run start before the installer lock is freed
    "Start-Sleep -Seconds 1" >> $tmp_script_path

    # add in the code for the target install, after all dependency code, and param block has been added via last index
    foreach($script in $tmp_script_contents) {
        $script >> $tmp_script_path
    }
}



# construct a wsb that will execute run.ps1 on startup 
$wsb_template  = @"
<Configuration>
<MappedFolders>
    <MappedFolder>
        <HostFolder>$tmp_dir</HostFolder>
        <SandboxFolder>C:\Users\WDAGUtilityAccount\SandboxShare</SandboxFolder>
    </MappedFolder>
</MappedFolders>
<LogonCommand>
    <Command>powershell -executionpolicy unrestricted -command "start powershell { -noexit -file $sandbox_dir\run.ps1 $ScriptParameters}"</Command>
</LogonCommand>
</Configuration>
"@

# will display the local machine actions required to run, the verbatim script of what would be deployed on the VM, as well as the .wsb this script would produce and run
if ($WhatIf) {
    Write-Host "=== LOCAL MACHINE ACTIONS ===" -ForegroundColor Green
    Write-Host $whatif_action_buffer
    Write-Host "=== SCRIPT WHICH WOULD BE DEPLOYED ON VM ===" -ForegroundColor Green
    Get-Content -Raw $tmp_script_path | Write-Host
    # remove cached wsb/ps1
    Remove-Item -Path $tmp_script_path -ErrorAction SilentlyContinue
    Remove-Item -Path "$tmp_dir\run.wsb" -ErrorAction SilentlyContinue
    Write-Host "=== .wsb GENERATED ===" -ForegroundColor Green
    Write-Host $wsb_template
    exit 0
}

# output the wsb and run it
$wsb_template | Out-File "$tmp_dir\run.wsb"
Start-Process -FilePath "$tmp_dir\run.wsb" 

