USE [dbtools]
GO
/************************************************************************************************* 
 * StoredProcedure: [dbo].[CollectDatabaseSpaceUsage]
 * Creado por: Daniel Israel
 * Fecha de creación: 01 de abril de 2024
 * Descripción: Procedimiento almacenado para recoleccion de data de espacio usado en disco
 * GitHub: https://github.com/digarciab/dbtools
 *************************************************************************************************/
ALTER   PROCEDURE [dbo].[CollectDatabaseSpaceUsage]
AS
BEGIN
    SET NOCOUNT ON;

    -- Variables para almacenar el nombre de la base de datos y la base de datos principal
    DECLARE @DBName NVARCHAR(128);
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @MainDB NVARCHAR(128) = DB_NAME();  -- Obtener el nombre de la base de datos actual

    -- Cursor para iterar a través de las bases de datos
    DECLARE db_cursor CURSOR FOR
    SELECT name
    FROM sys.databases
    WHERE state_desc = 'ONLINE' AND name NOT IN ('master', 'tempdb', 'model', 'msdb');

    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @DBName;

    -- Iterar a través de las bases de datos y ejecutar sp_spaceused con @oneresultset = 1
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Construir el script dinámico para cambiar el contexto de la base de datos y ejecutar sp_spaceused con @oneresultset = 1
        SET @SQL = '
            -- Validar si ya existe data para esa BD en el día actual
            IF NOT EXISTS (
                SELECT 1
                FROM ' + QUOTENAME(@MainDB) + '.dbo.DatabaseSpaceUsage
                WHERE DatabaseName = ''' + @DBName + '''
                AND CAST(RecordDateTime AS DATE) = CAST(GETDATE() AS DATE)
            )
            BEGIN

				USE ' + QUOTENAME(@DBName) + ';

				-- Obtener información de espacio usado para la base de datos actual
				DECLARE @DatabaseSpaceUsed TABLE (
					[database_name] NVARCHAR(128),
					[database_size] NVARCHAR(50),
					[unallocated_space] NVARCHAR(50),
					[reserved] NVARCHAR(50),
					[data] NVARCHAR(50),
					[index_size] NVARCHAR(50),
					[unused] NVARCHAR(50)
				);

				-- Insertar los resultados de sp_spaceused en la variable de tabla con @oneresultset = 1
				INSERT INTO @DatabaseSpaceUsed EXEC sp_spaceused @oneresultset = 1;

				-- Obtener información del log
				DECLARE @LogSpace TABLE (
					[database_name] NVARCHAR(128),
					[log_used] DECIMAL(18, 2),
					[log_noused] DECIMAL(18, 2)
				);
           
				INSERT INTO @LogSpace
				SELECT 
					DB_NAME() AS [database_name],
					CAST(SUM(CAST(used_log_space_in_bytes AS BIGINT)) / 1048576.0 AS DECIMAL(18, 2)) AS [log_used],
					CAST(SUM(CAST(total_log_size_in_bytes AS BIGINT)) / 1048576.0 AS DECIMAL(18, 2)) - CAST(SUM(CAST(used_log_space_in_bytes AS BIGINT)) / 1048576.0 AS DECIMAL(18, 2)) AS [log_noused]
				FROM sys.dm_db_log_space_usage;

				-- Insertar los resultados a nivel de tabla (cabecera) en la tabla de cabecera con las conversiones necesarias
				INSERT INTO ' + QUOTENAME(@MainDB) + '.dbo.DatabaseSpaceUsage ([DatabaseName], [DatabaseSize], [UnallocatedSpace], [Reserved], [DataSize], [IndexSize], [Unused], [LogUsed], [LogUnused], [RecordDateTime], [RecordDate])
				SELECT 
					''' + @DBName + ''',
					TRY_CAST(REPLACE([database_size], '' MB'', '''') AS DECIMAL(18, 2)),
					TRY_CAST(REPLACE([unallocated_space], '' MB'', '''') AS DECIMAL(18, 2)),
					TRY_CAST(REPLACE([reserved], '' KB'', '''') AS DECIMAL(18, 2)) / 1024.0,
					TRY_CAST(REPLACE([data], '' KB'', '''') AS DECIMAL(18, 2)) / 1024.0,
					TRY_CAST(REPLACE([index_size], '' KB'', '''') AS DECIMAL(18, 2)) / 1024.0,
					TRY_CAST(REPLACE([unused], '' KB'', '''') AS DECIMAL(18, 2)) / 1024.0,
					[log_used],
					[log_noused],
					GETDATE(),
					CONVERT(DATE, GETDATE()) RecordDate
				FROM @DatabaseSpaceUsed, @LogSpace;

				-- Insertar los resultados a nivel de tabla (detalle) en la tabla de detalle
				INSERT INTO ' + QUOTENAME(@MainDB) + '.[dbo].[DatabaseTableSpaceUsage] ([DatabaseSpaceUsageId],[DatabaseName],[SchemaName],[TableName],[NumRows],[Reserved],[Used],[Unused],[RecordDateTime],[RecordDate])			
				SELECT IDENT_CURRENT(''' + @MainDB + '.dbo.DatabaseSpaceUsage'')  as DatabaseSpaceUsageId,
					''' + @DBName + ''' AS DatabaseName,
					s.Name AS SchemaName,
					t.Name AS TableName,
					p.rows AS NumRows,
					CAST(ROUND((SUM(a.total_pages) / 128.00), 2) AS NUMERIC(36, 2)) AS Reserved,
					CAST(ROUND((SUM(a.used_pages) / 128.00), 2) AS NUMERIC(36, 2)) AS Used,
					CAST(ROUND((SUM(a.total_pages) - SUM(a.used_pages)) / 128.00, 2) AS NUMERIC(36, 2)) AS Unused,
					GETDATE() RecordDateTime,
					CONVERT(DATE, GETDATE()) RecordDate
				FROM sys.tables t
					JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
					JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
					JOIN sys.allocation_units a ON p.partition_id = a.container_id
					LEFT OUTER JOIN sys.schemas s ON t.schema_id = s.schema_id
				WHERE t.name NOT LIKE ''dt%'' AND t.is_ms_shipped = 0 AND i.object_id > 255
				GROUP BY t.Name, s.Name, p.Rows;
			END
        ';

        -- Ejecutar el script dinámico
        EXEC sp_executesql @SQL;

        FETCH NEXT FROM db_cursor INTO @DBName;
    END

    -- Cerrar y liberar el cursor
    CLOSE db_cursor;
    DEALLOCATE db_cursor;
END
