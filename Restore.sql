/************************************************************************************************* 
 * Creado por: Daniel Israel
 * Fecha de creación: 01 de abril de 2024
 * Descripción: Script para restaurar BD
 * GitHub: https://github.com/digarciab/dbtools
 *************************************************************************************************/

DECLARE @DatabaseName NVARCHAR(128);
DECLARE @DatabaseNameDestino NVARCHAR(128);
DECLARE @PrefijoOrigen NVARCHAR(128);
DECLARE @PrefijoDestino NVARCHAR(128);
DECLARE @SufijoDestino NVARCHAR(128);
DECLARE @BackupPath NVARCHAR(256);
DECLARE @BackupFile NVARCHAR(512);
DECLARE @sql NVARCHAR(MAX);
DECLARE @moveSQL NVARCHAR(MAX);
DECLARE @UserName NVARCHAR(128);
DECLARE @LoginName NVARCHAR(128);
DECLARE @FileExists INT;

-- Asigna el nombre de la base de datos
SET @DatabaseName = 'Prd_Bai15';  -- Reemplaza esto con el nombre de tu base de datos o pasa este valor como parámetro

-- Asigna el nombre de la base de datos de destino
SET @PrefijoOrigen = 'Prd_';  -- Reemplaza esto con el prefijo de la base de datos de origen o pasa este valor como parámetro
SET @PrefijoDestino = 'Qa_';  -- Reemplaza esto con el prefijo de la base de datos de destino o pasa este valor como parámetro
SET @SufijoDestino = '_Ofu';  -- Dejar en blanco si no se requiere sufijo adicional

-- Genera el nombre de la base de datos de destino
SET @DatabaseNameDestino = REPLACE(@DatabaseName, @PrefijoOrigen, @PrefijoDestino) + @SufijoDestino;

-- Define la ruta del archivo de backup
SET @BackupPath = '\\fs-033dfa7c56c3f0b20.cma.aws\share\SQLBackup\';  -- Cambia esto a la ruta donde está almacenado el archivo de backup
SET @BackupFile = @BackupPath + @DatabaseName + '.bak';

-- Recupera los nombres lógicos de los archivos de datos y logs desde el archivo de backup
DECLARE @FileList TABLE (
    LogicalName NVARCHAR(128),
    PhysicalName NVARCHAR(260),
    [Type] CHAR(1),
    FileGroupName NVARCHAR(128),
    Size BIGINT,
    MaxSize BIGINT,
    FileId INT,
    CreateLSN NUMERIC(25,0),
    DropLSN NUMERIC(25,0),
    UniqueId UNIQUEIDENTIFIER,
    ReadOnlyLSN NUMERIC(25,0),
    ReadWriteLSN NUMERIC(25,0),
    BackupSizeInBytes BIGINT,
    SourceBlockSize INT,
    FileGroupId INT,
    LogGroupGUID UNIQUEIDENTIFIER,
    DifferentialBaseLSN NUMERIC(25,0),
    DifferentialBaseGUID UNIQUEIDENTIFIER,
    IsReadOnly BIT,
    IsPresent BIT,
    TDEThumbprint VARBINARY(32),
    SnapshotUrl NVARCHAR(360)
);

SET @sql = 'RESTORE FILELISTONLY FROM DISK = ''' + @BackupFile + '''';
INSERT INTO @FileList
EXEC(@sql);

-- Verificar si la base de datos dbtools existe
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'dbtools')
BEGIN
    RAISERROR('No existe la BD dbtools que es el template para la ubicación de archivos', 16, 1);
    RETURN;
END

-- Construye el comando MOVE para cada archivo de datos y logs
SET @moveSQL = '';
SELECT @moveSQL = @moveSQL + 
    CASE 
        WHEN [Type] = 'D' THEN 
            'MOVE ''' + LogicalName + ''' TO ''' + 
            LEFT(
                (SELECT physical_name FROM sys.master_files WHERE database_id = DB_ID('dbtools') AND type_desc = 'ROWS'),
                LEN((SELECT physical_name FROM sys.master_files WHERE database_id = DB_ID('dbtools') AND type_desc = 'ROWS'))+1 - CHARINDEX('\', REVERSE((SELECT physical_name FROM sys.master_files WHERE database_id = DB_ID('dbtools') AND type_desc = 'ROWS')))
            ) + REPLACE(LogicalName, @PrefijoOrigen, @PrefijoDestino) + @SufijoDestino + '.mdf'', '
        WHEN [Type] = 'L' THEN 
            'MOVE ''' + LogicalName + ''' TO ''' + 
            LEFT(
                (SELECT physical_name FROM sys.master_files WHERE database_id = DB_ID('dbtools') AND type_desc = 'LOG'),
                LEN((SELECT physical_name FROM sys.master_files WHERE database_id = DB_ID('dbtools') AND type_desc = 'LOG')) +1 - CHARINDEX('\', REVERSE((SELECT physical_name FROM sys.master_files WHERE database_id = DB_ID('dbtools') AND type_desc = 'LOG')))
            ) + REPLACE(LogicalName, @PrefijoOrigen, @PrefijoDestino) + @SufijoDestino + '.ldf'', '
    END
FROM @FileList;

-- Elimina la última coma y espacio
SET @moveSQL = LEFT(@moveSQL, LEN(@moveSQL) - 1);

-- Verificar si la base de datos de destino existe
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = @DatabaseNameDestino)
BEGIN
	-- Generar el comando KILL para todas las sesiones activas en la base de datos antigua
	SET @sql = '';
	SELECT @sql = @sql + N'KILL ' + CONVERT(VARCHAR(5), spid) + N';'
	FROM sysprocesses p
	JOIN sysdatabases d ON p.dbid = d.dbid
	WHERE d.name = @DatabaseNameDestino;
    -- Si existe, ejecutar el comando KILL para las sesiones activas
    EXEC sp_executesql @sql;
	
    -- Luego, cambiar a modo de usuario único
    SET @sql = '
    ALTER DATABASE [' + @DatabaseNameDestino + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
    -- Ejecutar el comando SQL
    EXEC sp_executesql @sql;
END

-- Construye el comando RESTORE DATABASE
SET @sql = '
RESTORE DATABASE [' + @DatabaseNameDestino + '] 
FROM DISK = ''' + @BackupFile + ''' 
WITH ' + @moveSQL + ', REPLACE;
ALTER DATABASE [' + @DatabaseNameDestino + '] SET MULTI_USER;';

-- Opcionalmente, imprime el comando generado (para depuración)
-- PRINT @sql;

-- Ejecuta el comando de restauración
EXEC sp_executesql @sql;

-- Generar el nombre del usuario y login basado en el nombre de la base de datos restaurada
SET @UserName = UPPER(REPLACE(@DatabaseNameDestino, @SufijoDestino, ''))+ '_DBO';

SET @LoginName = @UserName;

SET @sql = '
	USE [' + @DatabaseNameDestino + '];
	
	BEGIN TRY
		-- Verifica si el usuario ya existe
		IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = ''' + @UserName + ''')
		BEGIN
			-- Si el usuario no existe, lo crea
			CREATE USER [' + @UserName + '] FOR LOGIN [' + @LoginName + '];
		END

		-- Establece el esquema predeterminado y asigna el rol db_owner
		ALTER USER [' + @UserName + '] WITH DEFAULT_SCHEMA=[dbo];
		ALTER ROLE [db_owner] ADD MEMBER [' + @UserName + '];
	END TRY
	BEGIN CATCH
		-- Si ocurre un error, imprime un mensaje y maneja el error
		PRINT ''Error al intentar crear o modificar el usuario: '' + ERROR_MESSAGE();
	END CATCH;
';

-- Ejecuta el comando dinámico
EXEC sp_executesql @sql;

-- Verifica si el archivo ya existe
EXEC xp_fileexist @BackupFile, @FileExists OUTPUT;

-- Si el archivo existe (valor 1), lo elimina
IF @FileExists = 1
BEGIN
    EXEC xp_delete_file 0, @BackupFile;
END
