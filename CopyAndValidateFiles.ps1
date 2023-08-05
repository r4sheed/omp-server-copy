<#
.SYNOPSIS
Automated File Copy and Server File Validation Script.

.DESCRIPTION
This PowerShell script automates the process of copying files based on specified settings and validates the presence of required server files. It can copy entire folder structures and files based on patterns.

.PARAMETER SettingsFile
The path to the JSON settings file containing configuration details for the script.

.EXAMPLE
.\CopyAndValidateFiles.ps1 -SettingsFile "C:\Scripts\settings.json"
Runs the script using the provided settings file.

.NOTES
File: CopyAndValidateFiles.ps1
Author: rasheed
Date: August 5, 2023
Version: 1.0
#>

param (
    [string]$SettingsFile = "settings.json"
)

function ValidateAndDownloadServer {
    <#
    .SYNOPSIS
    Checks if server files are missing and downloads them if necessary.

    .DESCRIPTION
    This function checks if the server files are missing in the components folder and the omp-server file is missing in the root folder. If any files are missing, it downloads and extracts them.

    .PARAMETER settings
    The settings object containing the target folder path and the URL to download the server files from.

    .EXAMPLE
    $settings = @{
        target = "C:\Server"
        url = "http://example.com/server.tar.gz"
    }
    ValidateAndDownloadServer -TargetPath $settings.target -URL $settings.url
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TargetPath,
        
        [Parameter(Mandatory = $true)]
        [string]$URL
    )

    try {
		# Throw an error if the target directory doesn't exist.
        if (-not (Test-Path -Path $TargetPath -PathType Container)) {
			Write-Warning "Target path '$TargetPath' is not exists, creating directory."

            New-Item -Path $TargetPath -ItemType Directory -Force
        }

        # Define the list of server files to check
        $componentFiles = @(
            "Actors.so",
            "Checkpoints.so",
            "Classes.so",
            "Console.so",
            "CustomModels.so",
            "Databases.so",
            "Dialogs.so",
            "Fixes.so",
            "GangZones.so",
            "LegacyConfig.so",
            "LegacyNetwork.so",
            "Menus.so",
            "Objects.so",
            "Pawn.so",
            "Pickups.so",
            "TextDraws.so",
            "TextLabels.so",
            "Timers.so",
            "Unicode.so",
            "Variables.so",
            "Vehicles.so"
        )

        # Check if omp-server file exists in the root folder
        $server = Join-Path $TargetPath "omp-server"

        # Check if any server files are missing in the components folder
        $components = $componentFiles | Where-Object { -not (Test-Path (Join-Path $TargetPath "components\$_") -PathType Leaf) }

        if (-not (Test-Path $server -PathType Leaf) -or $components.Count -gt 0) {
            Write-Host "One or more server files are missing. Downloading and extracting..."

			# Download the server files
			$downloadPath = Join-Path $TargetPath "server.tar.gz"
			Write-Host "Downloading file from '$URL' to '$downloadPath'"
            Invoke-WebRequest -Uri $URL -OutFile $downloadPath

            # Extract the downloaded file to the root folder
            Write-Host "Extracting file to '$TargetPath'"
            tar -xzf $downloadPath -C $TargetPath --strip-components 1

            # Delete the downloaded file
            Write-Host "Deleting downloaded file '$downloadPath'"
            Remove-Item $downloadPath -Force
        }

        return $true
    }
    catch {
        Write-Error $_.Exception.Message
    }
}

<#
.SYNOPSIS
Copy files based on structure settings from source to target.

.DESCRIPTION
This function copies files and folders based on the provided structure settings from a source directory to a target directory. It supports copying entire folder structures and files based on patterns.

.PARAMETER Source
The source directory path.

.PARAMETER Target
The target directory path.

.PARAMETER Structure
A hashtable representing the structure settings, including "folder", "includes".

.EXAMPLE
Copy-Files -Source "C:\Source" -Target "C:\Target" -Structure $structure

#>

function Copy-Files {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Target,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSCustomObject]$Structure
    )
    
    $Folder = $Structure.folder
    $Includes = $Structure.includes

    foreach ($include in $Includes) {
        if ($include.EndsWith('/') -or $include.EndsWith('\')) {
            # Copy the entire folder structure
            $includePath = Join-Path -Path $Source -ChildPath $include.TrimEnd('/', '\')
            if (-not (Test-Path -Path $Target -PathType Container)) {
                New-Item -Path $Target -ItemType Directory -Force
            }
            Write-Debug $Target
            Copy-Item -Path $includePath -Destination $Target -Recurse -Force
        } else {
            # Copy files based on the pattern
            $filesToCopy = Get-ChildItem -Path $Source -Recurse | Where-Object { 
                $_.Name -like $include -and -not ($_ | Test-Path -PathType Container) 
            }
            
            foreach ($file in $filesToCopy) {
                $relativePath = $file.FullName.Substring($Source.Length)
                $destination = Join-Path -Path $Target -ChildPath $relativePath
                if (-not (Test-Path -Path (Split-Path -Path $destination -Parent) -PathType Container)) {
                    New-Item -Path (Split-Path -Path $destination -Parent) -ItemType Directory -Force
                }
                Write-Debug $destination
                Copy-Item -Path $file.FullName -Destination $destination -Force
            }
        }
    }
}

try {
    # Enable debug
    # $DebugPreference = "Continue"

    # If the settings file does not exist, create it with default settings
    if (-not (Test-Path -Path $SettingsFile -PathType Leaf)) {
        $defaultSettings = @{
            source = "C:\SourcePath"
            target = "C:\TargetPath"
            url = "https://github.com/openmultiplayer/open.mp/releases/download/v1-RC2/open.mp-linux-x86.tar.gz"
            structure = @(
                @{
                    folder = "filterscripts"
                    includes = @("*.amx")
                }
                @{
                    folder = "gamemodes"
                    includes = @("*.amx")
                }
                @{
                    folder = "plugins"
                    includes = @("*.so")
                }
                @{
                    folder = "scriptfiles"
                    includes = @("*.ini")
                }
            )
        }
        
        $defaultSettings | ConvertTo-Json | Set-Content -Path $SettingsFile -Force
        Write-Host "Default settings file created at '$SettingsFile'. Please customize it and run the script again."
        return
    }

    # Read parameters from JSON file
    $settings = Get-Content -Path $SettingsFile -Raw | ConvertFrom-Json

    # Validate the presence of required properties in the settings object
    $requiredProperties = @("source", "target", "url", "structure")
    $missingProperties = $requiredProperties | Where-Object { -not $settings.PSObject.Properties.Name.Contains($_) }

    if ($missingProperties.Count -gt 0) {
        $missingProps = $missingProperties -join "', '"
        throw "The following required properties are missing from the settings file: '$missingProps'."
    }

    # Validate server files and if one of them is missing, automatically download and extract it to the target root folder.
    if (!(ValidateAndDownloadServer -TargetPath $settings.target -URL $settings.url)) {
        throw "Failed to validate or download server files."
    }

	# Loop through structure and copy files based on settings
	foreach ($item in $settings.structure) {
		$obj = @{
			folder = $item.folder
			includes = $item.includes
		}

		$sourceDir = Join-Path -Path $settings.source -ChildPath $item.folder
		$targetDir = Join-Path -Path $settings.target -ChildPath $item.folder

		Copy-Files -Source $sourceDir -Target $targetDir -Structure $obj
	}

    Write-Output "Task finished successfully."
    Write-Output "Press ENTER to exit..."

    Read-Host
}
catch {
    Write-Output $_	
    Write-Output "Press ENTER to exit..."

	Read-Host
}