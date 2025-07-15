# SandBox-Run
This was something I threw together because I test app deployments in the windows sandbox a lot currently.

## Pre-requisites
The windows sandbox feature needs to be enabled. 

## Status
Recently updated create an amalagamation of all scripts to be ran under one master script. There is a cleaner
way to do this but I wanted to try out the System.Management.Automation.Language API :p

## Usage 
- Packages flag: Packages to include in the sandbox. Currently only VSCode is included.
- Depends flag: Required libs to install before running the script(s)
- ScriptPath: Path to script to run in the sandbox
- ScriptList: A list of paths to scripts to run in sequence in the sandbox 



