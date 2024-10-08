USE [dbtools]
GO
/************************************************************************************************* 
 * StoredProcedure: [dbo].[BackupDatabases] 
 * Creado por: Daniel Israel
 * Fecha de creación: 01 de abril de 2024
 * Descripción: Procedimiento almacenado para realizar backups automáticos de bases de datos, verificar la existencia de rutas, y gestionar la retención de backups.
 * GitHub: https://github.com/digarciab/dbtools
 *************************************************************************************************/
ALTER   PROCEDURE [dbo].[BackupDatabases]
    @BackupPath NVARCHAR(500),
    @MaxDatabaseSizeMB INT = 5120,  -- Tamaño máximo de la base de datos en MB (5GB por defecto)
    @BackupsToRetain INT = 5  -- Número de backups a retener por día (5 por defecto)
AS
BEGIN
    SET NOCOUNT ON;

    -- Asegurarse de que @BackupPath termine en '\'
    IF RIGHT(@BackupPath, 1) <> '\'
    BEGIN
        SET @BackupPath = @BackupPath + '\';
    END

    DECLARE @BackupPathFull NVARCHAR(500)
    DECLARE @DatabaseName NVARCHAR(255)
    DECLARE @BackupName NVARCHAR(255)
    DECLARE @Date NVARCHAR(30)
    DECLARE @sql NVARCHAR(MAX)
    DECLARE @BackupFile NVARCHAR(255)
    DECLARE @FileExists INT

    -- Crear una tabla temporal para almacenar los resultados de xp_fileexist
    CREATE TABLE #FileCheck (    
        FileExists INT,
        IsDirectory INT,
        ParentDirectory INT
    )

    -- Crear una tabla temporal para almacenar los archivos de backup
    CREATE TABLE #BackupFiles (
        BackupFile NVARCHAR(255),
        Depth INT,
        IsFile BIT,
        BackupDate DATETIME
    )

    -- Ejecutar xp_fileexist para la ruta base y capturar los resultados en la tabla temporal
    INSERT INTO #FileCheck (FileExists, IsDirectory, ParentDirectory)
    EXEC master.dbo.xp_fileexist @BackupPath

    -- Verificar si la ruta base existe y es un directorio
    DECLARE @IsBaseDirectory INT
    SELECT @IsBaseDirectory = IsDirectory
    FROM #FileCheck

    IF @IsBaseDirectory = 1
    BEGIN
        PRINT 'La ruta inicial para los backups existe: ' + @BackupPath;

        -- Cursor para recorrer todas las bases de datos online que pesen menos de @MaxDatabaseSizeMB MB
        DECLARE db_cursor CURSOR FOR
        SELECT 
            d.name
        FROM sys.databases d
        JOIN sys.master_files f ON d.database_id = f.database_id
        GROUP BY d.name
        HAVING SUM(f.size * 8 / 1024.0) < @MaxDatabaseSizeMB
        AND d.name NOT IN ('master', 'tempdb', 'model', 'msdb', 'distribution','ReportServer','ReportServerTempDB') -- Excluyendo bases de datos del sistema

        OPEN db_cursor
        FETCH NEXT FROM db_cursor INTO @DatabaseName

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- Configurar el nombre del archivo de backup
            SET @Date = FORMAT(SYSDATETIME(), 'yyyy_MM_dd_HHmmss_fffffff');
            SET @BackupPathFull = @BackupPath + @DatabaseName + '\'
            SET @BackupName = @BackupPathFull + @DatabaseName + '_backup_' + @Date + '.bak';

            TRUNCATE TABLE #FileCheck
            -- Ejecutar xp_fileexist para la carpeta específica y capturar los resultados en la tabla temporal
            INSERT INTO #FileCheck (FileExists, IsDirectory, ParentDirectory)
            EXEC master.dbo.xp_fileexist @BackupPathFull

            -- Verificar la existencia de la carpeta específica
            DECLARE @IsSpecificDirectory INT
            SELECT @IsSpecificDirectory = IsDirectory
            FROM #FileCheck

            IF @IsSpecificDirectory = 1
            BEGIN
                PRINT 'La carpeta específica para la base de datos existe: ' + @BackupPathFull;
                SET @sql = 'BACKUP DATABASE [' + @DatabaseName + '] TO DISK = ''' + @BackupName + ''' WITH INIT, COMPRESSION;'
                EXEC sp_executesql @sql
            END
            ELSE
            BEGIN
                SET @BackupName = @BackupPath + @DatabaseName + '_backup_' + @Date + '.bak';			
                SET @BackupPathFull = @BackupPath;
                SET @sql = 'BACKUP DATABASE [' + @DatabaseName + '] TO DISK = ''' + @BackupName + ''' WITH INIT, COMPRESSION;'
                EXEC sp_executesql @sql
                PRINT 'La carpeta específica no existe. Backup realizado en la ruta inicial: ' + @BackupPath;
            END

            TRUNCATE TABLE #BackupFiles
            INSERT INTO #BackupFiles (BackupFile, Depth, IsFile)
            EXEC master.sys.xp_dirtree @BackupPathFull, 1, 1;

            UPDATE #BackupFiles
            SET BackupDate = TRY_CAST(
                            SUBSTRING(BackupFile, LEN(@DatabaseName) + 9, 4) + '-' + 
                            SUBSTRING(BackupFile, LEN(@DatabaseName) + 14, 2) + '-' +
                            SUBSTRING(BackupFile, LEN(@DatabaseName) + 17, 2) + ' ' + 
                            SUBSTRING(BackupFile, LEN(@DatabaseName) + 20, 2) + ':' +
                            SUBSTRING(BackupFile, LEN(@DatabaseName) + 22, 2) + ':' +
                            SUBSTRING(BackupFile, LEN(@DatabaseName) + 24, 2) 
                            AS DATETIME)
            WHERE IsFile = 1 AND BackupFile LIKE @DatabaseName + '_backup_%.bak';

            DECLARE delete_cursor CURSOR FAST_FORWARD FOR
            WITH BackupRanked AS (
                SELECT 
                    BackupFile,
                    BackupDate,
                    ROW_NUMBER() OVER (PARTITION BY CAST(BackupDate AS DATE) ORDER BY BackupDate DESC) AS DailyRank,
                    ROW_NUMBER() OVER (ORDER BY BackupDate DESC) AS OverallRank
                FROM #BackupFiles
                WHERE BackupDate IS NOT NULL
            ),
            LastBackupOfPreviousDay AS (
                SELECT MAX(BackupDate) AS LastBackupDate
                FROM BackupRanked
                WHERE CAST(BackupDate AS DATE) = CAST(DATEADD(DAY, -1, GETDATE()) AS DATE)
            )
            SELECT BackupFile
            FROM BackupRanked
            WHERE (CAST(BackupDate AS DATE) = CAST(GETDATE() AS DATE) AND DailyRank > @BackupsToRetain) OR 
                (CAST(BackupDate AS DATE) <> CAST(GETDATE() AS DATE) AND BackupDate < (SELECT LastBackupDate FROM LastBackupOfPreviousDay));

            OPEN delete_cursor;

            FETCH NEXT FROM delete_cursor INTO @BackupFile;

            WHILE @@FETCH_STATUS = 0
            BEGIN
                DECLARE @FullBackupPath NVARCHAR(500) = @BackupPathFull + @BackupFile;
                EXEC master.dbo.xp_fileexist @FullBackupPath, @FileExists OUTPUT;

                IF @FileExists = 1
                BEGIN
                    EXEC master.dbo.xp_delete_file 0, @FullBackupPath, N'File';
                END
                ELSE
                BEGIN
                    PRINT 'El archivo no existe: ' + @FullBackupPath;
                END
                
                FETCH NEXT FROM delete_cursor INTO @BackupFile;
            END

            CLOSE delete_cursor;
            DEALLOCATE delete_cursor;

            FETCH NEXT FROM db_cursor INTO @DatabaseName
        END

        CLOSE db_cursor
        DEALLOCATE db_cursor
    END
    ELSE
    BEGIN
        PRINT 'La ruta inicial para los backups no existe o no es un directorio: ' + @BackupPath;
    END

    -- Limpiar las tablas temporales
    DROP TABLE #FileCheck;
    DROP TABLE #BackupFiles;
END
