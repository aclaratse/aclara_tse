# Step 1: Find the location of Job scheduler directory
$jobSchedulerDir = Get-ChildItem -Path "J:\" -Recurse -Directory -Filter "Job Scheduler" -ErrorAction SilentlyContinue

if ($jobSchedulerDir -eq $null) {
    Write-Host "Job Scheduler directory not found."
    exit
}

# Step 2: Find the latest log file
$logFile = Get-ChildItem -Path $jobSchedulerDir.FullName -Filter "Aclara.iiDEAS.Scheduler.WinService.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($logFile -eq $null) {
    Write-Host "Log file not found."
    exit
}
else {
    Write-Host "Found log file"
}

# Step 3: Find the configuration file
$configFile = Get-ChildItem -Path $jobSchedulerDir.FullName -Filter "Aclara.iiDEAS.Scheduler.WinService.exe.config" -ErrorAction SilentlyContinue

if ($configFile -eq $null) {
    Write-Host "Configuration file not found."
    exit
}
else {
    Write-Host "Found config file"
}

# Step 4: Update the configuration file with new values

Copy-Item -Path $configFile.FullName -Destination ".\Aclara.iiDEAS.Scheduler.WinService.exe.config.backup" -Force
Write-Host "Backed up config file"
Get-Service -DisplayName "AclaraONE Job Scheduler Service" | Stop-Service -Force
Write-host "Stopping job scheduler service"

$configContent = Get-Content -Path $configFile.FullName

$configContent = $configContent -replace '<add key="DailyShiftSyncRunIntervalForFirstTime" value="\d+"/>', '<add key="DailyShiftSyncRunIntervalForFirstTime" value="1"/>'
$configContent = $configContent -replace '<add key="DailyShiftSyncRunIntervalInDays" value="\d+"/>', '<add key="DailyShiftSyncRunIntervalInDays" value="1"/>'
$configContent = $configContent -replace '<add key="syncAmrIntervalDataDurationInNewTable_Day" value="\d+"/>', '<add key="syncAmrIntervalDataDurationInNewTable_Day" value="1"/>'
$configContent = $configContent -replace '<add key="SyncIntervalDataCacheInMinutes" value="\d+"/>', '<add key="SyncIntervalDataCacheInMinutes" value="1440"/>'
$configContent = $configContent -replace '<add key="syncAttemptSecondTimeForIntervalData" value="\d+"/>', '<add key="syncAttemptSecondTimeForIntervalData" value="1"/>'
$configContent = $configContent -replace '<add key="DailyShiftCacheRunIntervalInMinutes" value="\d+"/>', '<add key="DailyShiftCacheRunIntervalInMinutes" value="1440"/>'
$configContent = $configContent -replace '<add key="CommandTimeoutInSeconds" value="\d+"/>', '<add key="CommandTimeoutInSeconds" value="1200"/>'

Set-Content -Path $configFile.FullName -Value $configContent

Write-Host "Configuration file updated successfully."

# Read the file content
$fileContent = Get-Content $configFile.FullName

# Define regex patterns for SQL Server and Oracle connection strings
$sqlPattern = "name=`"iiDEAS`""
$oraclePattern = "providerName=`"Oracle.ManagedDataAccess.Client`""

# RegEx
$serverpattern = "(?<=Server=)[^;]+"
$databasepattern = '(?<=Database=)[^;]+'
$usernamepattern = '(?<=User ID=)[^;]+'
$passwordpattern = '(?<=Password=)[^"]+'

foreach($line in $fileContent) {
    if ($line -match $sqlpattern) {
        $msdatabase = [regex]::Matches($line, $databasepattern).Value
        $msusername = [regex]::Matches($line, $usernamepattern).Value
        $mspassword = [regex]::Matches($line, $passwordpattern).Value
        $msservername = [regex]::Matches($line, $serverpattern).Value
    }
    elseif ($line -match $oraclePattern) {
        $oradatabase = [regex]::Matches($line, '(?<=SERVICE_NAME =)[^)]+').Value
        $orausername = [regex]::Matches($line, '(?<=user id=)[^;]+').Value
        $orapassword = [regex]::Matches($line, '(?<=password=)[^;]+').Value
        $oraservername = [regex]::Matches($line, "(?<=HOST =)[^)]+").Value.trim()
    }
}

# Define the connection string
$connectionString = "Data Source=$msservername\$msdatabase;Initial Catalog=$msdatabase;User Id=$msusername;Password=$mspassword;"

$query1 = "truncate table Ami_DevicePropertyValues;"
$query2 = "truncate table Ami_DistinctPropertyValues;"
# Create and open a connection to the SQL Server
$connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
$command1 = new-object system.data.sqlclient.sqlcommand($query1,$connection)
$command2 = new-object system.data.sqlclient.sqlcommand($query2,$connection)
$connection.Open()

# Execute the query and load the results into a DataTable
$adapter1 = New-Object System.Data.SqlClient.SqlDataAdapter $command1
$adapter2 = New-Object System.Data.SqlClient.SqlDataAdapter $command2
$dataset1 = New-Object System.Data.DataSet
$adapter1.Fill($dataset1)
$dataset1 = New-Object System.Data.DataSet

# Display the results
$dataset1.Tables[0] | Format-Table -AutoSize

# Close the connection
$connection.Close()

Get-Service -DisplayName "AclaraONE Job Scheduler Service" | Start-Service -Force
Write-Host "Started job scheduler service"