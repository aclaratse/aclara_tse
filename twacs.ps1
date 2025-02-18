param(
    [Parameter(Mandatory=$true, ParameterSetName='QuerySet')]
    [string[]]$QueryName,
    
    [Parameter(Mandatory=$true, ParameterSetName='CommandSet')]
    [string[]]$os_cmd
    )

# Configuration
$jsonPath = ".\queries.json"
$sqlplusPath = "sqlplus"  # Assumes sqlplus is in PATH, otherwise specify full path

# Oracle connection details
$oracleUser = "dcsi"
$oraclePassword = "DCSI"
$oracleSid = "METER"
$oracleCredentials = "$oracleUser/$oraclePassword@$oracleSid"

# Function to validate if sqlplus is available
function Test-SqlPlus {
    try {
        $null = Get-Command $sqlplusPath -ErrorAction Stop
        return $true
    }
    catch {
        Write-Error "SQLPlus not found. Please ensure Oracle client is installed and sqlplus is in PATH"
        return $false
    }
} #>

# Function to validate JSON file
function Test-JsonFile {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        Write-Error "Query file not found: $Path"
        return $false
    }
    
    try {
        $null = Get-Content $Path | ConvertFrom-Json
        return $true
    }
    catch {
        Write-Error "Invalid JSON format in query file: $Path"
        return $false
    }
}

# Function to get query from JSON
function Get-QueryFromJson {
    param(
        [string]$QueryName,
        [string]$JsonPath
    )
    
    $queries = Get-Content $JsonPath | ConvertFrom-Json
    
    if (-not $queries.PSObject.Properties.Value -contains $QueryName) {
        Write-Error "Query '$QueryName' not found in JSON file"
        return $null
    }
    
    return $queries.$QueryName
}

# Function to get PowerShell command from JSON
function Get-CommandFromJson {
    param(
        [string]$CommandName,
        [string]$JsonPath
    )
    
    $commands = Get-Content $JsonPath | ConvertFrom-Json
    
    if (-not ($commands.PSObject.Properties.Name -contains $CommandName)) {
        Write-Error "Command '$CommandName' not found in JSON file"
        return $null
    }
    
    return $commands.$CommandName
}

# Function to execute PowerShell command
function Invoke-JsonCommand {
    param(
        [string]$Command
    )
    
    try {
        $scriptBlock = [ScriptBlock]::Create($Command)
        & $scriptBlock
    }
    catch {
        Write-Error "Error executing PowerShell command: $_"
        return $null
    }
}
# Function to execute query using sqlplus
function Invoke-OracleQuery {
    param(
        [string]$Query,
        [string]$Credentials
    )
    
    # Create temp SQL file
    $tempFile = [System.IO.Path]::GetTempFileName()
    
    try {
        @"
SET PAGESIZE 50000
SET LINESIZE 10000
SET LINES 5000
SET FEEDBACK ON
SET HEADING ON
SET ECHO ON
SET TIMING ON
SET WRAP OFF

$Query

EXIT;
"@ | Out-File -FilePath $tempFile -Encoding ASCII
        
        # Execute query
        $result = & $sqlplusPath -S $Credentials "@$tempFile"
        return $result
    }
    catch {
        Write-Error "Error executing query: $_"
        return $null
    }
    finally {
        # Cleanup temp file
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force
        }
    }
}

# Main 
if (-not (Test-SqlPlus)) {
    exit 1
}

if (-not (Test-JsonFile $jsonPath)) {
    exit 1
}

if ($PSCmdlet.ParameterSetName -eq 'QuerySet') {
    if (-not (Test-SqlPlus)) {
        exit 1
    }
    
    $query = Get-QueryFromJson -QueryName $QueryName -JsonPath $jsonPath
    if ($null -eq $query) {
        exit 1
    }

    # Execute query and display results
    $results = Invoke-OracleQuery -Query $query -Credentials $oracleCredentials
    if ($null -ne $results) {
        $results | ForEach-Object { Write-Output $_ }
    }
}
else {
    $command = Get-CommandFromJson -CommandName $os_cmd -JsonPath $jsonPath
    if ($null -eq $command) {
        exit 1
    }

    # Execute PowerShell command and display results
    $results = Invoke-JsonCommand -Command $command
    if ($null -ne $results) {
        $results | ForEach-Object { Write-Output $_ }
    }
}