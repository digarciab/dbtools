/************************************************************************************************* 
 * Creado por: Daniel Israel
 * Fecha de creación: 01 de abril de 2024
 * Descripción: Script para hacer Backup de BD
 * GitHub: https://github.com/digarciab/dbtools
 *************************************************************************************************/

DECLARE @DatabaseName NVARCHAR(128);
DECLARE @BackupPath NVARCHAR(256);
DECLARE @BackupFileName NVARCHAR(512);
DECLARE @sql NVARCHAR(MAX);
DECLARE @FileExists INT;

-- Asigna el nombre de la base de datos
SET @DatabaseName = 'Prd_Bai15';  -- Reemplaza esto con el nombre de tu base de datos o pasa este valor como parámetro

-- Define la ruta donde se almacenará el backup
SET @BackupPath = '\\fs-033dfa7c56c3f0b20\share\SQLBackup\';  -- Cambia esto a la ruta donde deseas almacenar el backup

-- Genera el nombre del archivo
SET @BackupFileName = @BackupPath + @DatabaseName + '.bak';

-- Verifica si el archivo ya existe
EXEC xp_fileexist @BackupFileName, @FileExists OUTPUT;

-- Si el archivo existe (valor 1), lo elimina
IF @FileExists = 1
BEGIN
    EXEC xp_delete_file 0, @BackupFileName;
END

-- Construye el comando BACKUP DATABASE
SET @sql = 'BACKUP DATABASE [' + @DatabaseName + '] TO DISK = ''' + @BackupFileName + ''' WITH INIT, COMPRESSION, NAME = ''' + @DatabaseName + ' Full Backup''';

-- Ejecuta el comando de backup
EXEC sp_executesql @sql;

-- Opcionalmente, imprime el comando generado (para depuración)
PRINT @sql;
