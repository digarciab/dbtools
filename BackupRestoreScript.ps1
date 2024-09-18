###################################################################################################
# Creado por: Daniel Israel
# Fecha de creación: 01 de abril de 2024
# Descripción: Script PS que ejecuta Script SQL
# GitHub: https://github.com/digarciab/dbtools
###################################################################################################

# Configuración de parámetros de Servidor
$server1 = ""
$server2 = ""

# Lista de servidores no permitidos
$notAllowedServers = @("SERVER01", "server01.empresa.com", "192.168.XX.XX") # Agrega aquí los nombres de los servidores no permitidos

# Parámetros de Rutas de archivos T-SQL
$backupScriptPath = "D:\dba\Backup.sql" # Ruta del archivo .sql para el backup
$restoreScriptPath = "D:\dba\Restore.sql" # Ruta del archivo .sql para el restore
$truncateScriptPath = "D:\dba\TruncateLogs.sql" # Ruta del archivo .sql para el Truncate de Logs
$obfuscateAlfanumericoScriptPath = "D:\dba\OfuscaAlfanumerico.sql" # Ruta del archivo .sql para ofuscar
$obfuscateEnteroScriptPath = "D:\dba\OfuscaEntero.sql" # Ruta del archivo .sql para ofuscar
$obfuscateDecimalScriptPath = "D:\dba\OfuscaDecimal.sql" # Ruta del archivo .sql para ofuscar

# Parámetros de Ruta donde se encuentran los archivos .bak
$backupFolderPath = "" 

# Parámetros de autenticación
$authType = "Integrada" # Puede ser "Integrada" o "SQL"
$sqlUser = "" # Usuario SQL en caso de autenticación SQL
$sqlPassword = "" # Contraseña en caso de autenticación SQL

# Función para ejecutar archivos SQL en un servidor con manejo de tiempo de espera
function Invoke-SqlScript {
    param (
        [string]$serverInstance,
        [string]$scriptPath,
        [int]$timeout = 0, # 0 indica sin límite de tiempo
        [string]$authType,
        [string]$sqlUser,
        [string]$sqlPassword
    )
    
    if ($authType -eq "SQL") {
        $connectionString = "Server=$serverInstance;User ID=$sqlUser;Password=$sqlPassword;Connection Timeout=$timeout;"
    } else {
        $connectionString = "Server=$serverInstance;Integrated Security=True;Connection Timeout=$timeout;"
    }

    $sqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $sqlConnection.ConnectionString = $connectionString
    $sqlConnection.Open()
    $script = Get-Content -Path $scriptPath -Raw
    $sqlCommand = $sqlConnection.CreateCommand()
    $sqlCommand.CommandText = $script
    $sqlCommand.CommandTimeout = $timeout
    try {
        $sqlCommand.ExecuteNonQuery()
        Write-Output "Script $scriptPath ejecutado exitosamente en $serverInstance."
    } catch {
        Write-Output "Error al ejecutar script $scriptPath en $serverInstance"
        exit 1
    } finally {
        $sqlConnection.Close()
    }
}

# Paso 0: Verificar si el servidor destino especificado sea permitido
if ($notAllowedServers -contains $server2) {
    Write-Output "El servidor $server2 no está permitido para restauración. No se realizará ninguna operación."
    exit
}

# Paso 1: Ejecutar el script de backup en el Servidor1
Write-Output "Ejecutando backup en $server1..."
Invoke-SqlScript -serverInstance $server1 -scriptPath $backupScriptPath -timeout 3600 -authType $authType -sqlUser $sqlUser -sqlPassword $sqlPassword
Write-Output "Backup completado en $server1."

# Paso 2: Ejecutar el script de restore en el Servidor2
Write-Output "Ejecutando restore en $server2..."
Invoke-SqlScript -serverInstance $server2 -scriptPath $restoreScriptPath -timeout 3600 -authType $authType -sqlUser $sqlUser -sqlPassword $sqlPassword
Write-Output "Restore completado en $server2."

# Paso 3: Ejecutar el script de ofuscamiento en el Servidor2
Write-Output "Ejecutando ofuscamiento en $server2..."
Invoke-SqlScript -serverInstance $server2 -scriptPath $obfuscateAlfanumericoScriptPath -timeout 3600 -authType $authType -sqlUser $sqlUser -sqlPassword $sqlPassword
Invoke-SqlScript -serverInstance $server2 -scriptPath $obfuscateEnteroScriptPath -timeout 3600 -authType $authType -sqlUser $sqlUser -sqlPassword $sqlPassword
Invoke-SqlScript -serverInstance $server2 -scriptPath $obfuscateDecimalScriptPath -timeout 3600 -authType $authType -sqlUser $sqlUser -sqlPassword $sqlPassword
Write-Output "Ofuscamiento completado en $server2."

# Paso 4: Ejecutar el script de truncado de logs en el Servidor2
Write-Output "Ejecutando truncado de logs en $server2..."
Invoke-SqlScript -serverInstance $server2 -scriptPath $truncateScriptPath -timeout 3600 -authType $authType -sqlUser $sqlUser -sqlPassword $sqlPassword
Write-Output "Truncado de Logs completado en $server2."

Write-Output "Proceso de backup, restore y ofuscamiento completado."
