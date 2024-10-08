USE [dbtools]
GO
/************************************************************************************************* 
 * StoredProcedure: [dbo].[ListaFragmentacionIndices]
 * Creado por: Daniel Israel
 * Fecha de creación: 01 de abril de 2024
 * Descripción: Procedimiento almacenado para listar el nivel de fragmentacion de los indices
 * GitHub: https://github.com/digarciab/dbtools
 *************************************************************************************************/
ALTER PROCEDURE [dbo].[ListaFragmentacionIndices]
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @sql NVARCHAR(MAX);
    DECLARE @databaseName NVARCHAR(128);
    DECLARE @MainDB NVARCHAR(128) = DB_NAME();  -- Obtener el nombre de la base de datos actual

    -- Cursor para recorrer todas las bases de datos
    DECLARE db_cursor CURSOR FOR
    SELECT name
    FROM sys.databases
    WHERE state_desc = 'ONLINE' AND name NOT IN ('master', 'tempdb', 'model', 'msdb');

    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @databaseName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = N'
            -- Validar si ya existe data para esa BD en el día actual
            IF NOT EXISTS (
                SELECT 1
                FROM ' + QUOTENAME(@MainDB) + '.dbo.IndexFragmentationHistory
                WHERE DatabaseName = ''' + @databaseName + '''
                AND CAST(RecordDate AS DATE) = CAST(GETDATE() AS DATE)
            )
            BEGIN
                USE ' + QUOTENAME(@databaseName) + ';
                INSERT INTO ' + QUOTENAME(@MainDB) + '.dbo.IndexFragmentationHistory (
                    RecordDate,
                    DatabaseName,
                    TableName,
                    IndexName,
                    IndexType,
                    IndexID,
                    FragmentationPercent,
                    FragmentCount,
                    AvgFragmentSizeInPages,
                    PageCount,
                    SizeMB,
                    UserSeeks,
                    UserScans,
                    UserLookups,
                    UserUpdates,
                    LastUserSeek,
                    LastUserScan,
                    LastUserLookup,
                    LastUserUpdate,
                    ActionRequired
                )
                SELECT
                    CAST(GETDATE() AS DATE) AS RecordDate,
                    ''' + @databaseName + ''' AS DatabaseName,
                    OBJECT_NAME(ips.object_id) AS TableName,
                    i.name AS IndexName,
                    i.type_desc AS IndexType,
                    ips.index_id,
                    COALESCE(ips.avg_fragmentation_in_percent, 0) AS avg_fragmentation_in_percent,
                    COALESCE(ips.fragment_count, 0) AS fragment_count,
                    COALESCE(ips.avg_fragment_size_in_pages, 0) AS avg_fragment_size_in_pages,
                    COALESCE(ips.page_count, 0) AS page_count,
                    COALESCE((ips.page_count * 8.0 / 1024), 0) AS SizeMB,
                    COALESCE(SUM(ius.user_seeks), 0) AS UserSeeks,
                    COALESCE(SUM(ius.user_scans), 0) AS UserScans,
                    COALESCE(SUM(ius.user_lookups), 0) AS UserLookups,
                    COALESCE(SUM(ius.user_updates), 0) AS UserUpdates,
                    MAX(ius.last_user_seek) AS LastUserSeek,
                    MAX(ius.last_user_scan) AS LastUserScan,
                    MAX(ius.last_user_lookup) AS LastUserLookup,
                    MAX(ius.last_user_update) AS LastUserUpdate,
                    CASE
                        WHEN COALESCE(ips.avg_fragmentation_in_percent, 0) >= 30 THEN ''Rebuild''
                        WHEN COALESCE(ips.avg_fragmentation_in_percent, 0) >= 5 THEN ''Reorganize''
                        ELSE ''None''
                    END AS ActionRequired
                FROM 
                    sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''LIMITED'') ips
                    JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
                    LEFT JOIN sys.dm_db_index_usage_stats ius ON ips.object_id = ius.object_id AND ips.index_id = ius.index_id AND ius.database_id = DB_ID()
                WHERE 
                    ips.database_id = DB_ID() and i.type_desc <> ''HEAP''
					AND COALESCE(ips.avg_fragmentation_in_percent, 0)>0
                GROUP BY 
                    ips.object_id,
                    i.name,
                    i.type_desc,
                    ips.index_id,
                    ips.avg_fragmentation_in_percent,
                    ips.fragment_count,
                    ips.avg_fragment_size_in_pages,
                    ips.page_count;
            END
        ';

        EXEC sp_executesql @sql;

        FETCH NEXT FROM db_cursor INTO @databaseName;
    END;

    CLOSE db_cursor;
    DEALLOCATE db_cursor;
END;
