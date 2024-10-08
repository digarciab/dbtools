USE [dbtools]
GO
/************************************************************************************************* 
 * StoredProcedure: [dbo].[RebuildFragmentedIndexes]
 * Creado por: Daniel Israel
 * Fecha de creación: 01 de abril de 2024
 * Descripción: Procedimiento almacenado para Reindexar la BD
 * GitHub: https://github.com/digarciab/dbtools
 *************************************************************************************************/
ALTER   PROCEDURE [dbo].[RebuildFragmentedIndexes]
AS
BEGIN
    DECLARE @DatabaseName NVARCHAR(128)
    DECLARE @TableName NVARCHAR(128)
    DECLARE @IndexName NVARCHAR(128)
    DECLARE @SchemaName NVARCHAR(128)
    DECLARE @RebuildSQL NVARCHAR(MAX)
    DECLARE @FullSQL NVARCHAR(MAX)
    DECLARE @IndexCursor CURSOR
    DECLARE @SchemaQuery NVARCHAR(MAX)
    DECLARE @CurrentTime TIME = CONVERT(TIME, GETDATE())

    -- Ventana horaria: 10 p.m. - 6 a.m.
    IF (@CurrentTime < '22:00' AND @CurrentTime >= '06:00')
    BEGIN
        PRINT 'El procedimiento solo se puede ejecutar entre las 10 p.m. y las 6 a.m.'
        RETURN
    END

    -- Cursor para recorrer los índices fragmentados
    SET @IndexCursor = CURSOR FOR
        SELECT DatabaseName, TableName, IndexName
        FROM IndexFragmentationHistory
        WHERE RecordDate = CONVERT(date, GETDATE())
          AND FragmentationPercent > 30
          AND SizeMB > 10
          AND DatabaseName IN (SELECT DatabaseName FROM RegisteredDatabases)
        ORDER BY cast(round(SizeMB, 0) as bigint) DESC

    OPEN @IndexCursor
    FETCH NEXT FROM @IndexCursor INTO @DatabaseName, @TableName, @IndexName

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            -- Cambiar el contexto a la base de datos adecuada
            SET @SchemaQuery = 'USE [' + @DatabaseName + ']; ' + 
                               'SELECT @SchemaName = s.name ' +
                               'FROM sys.tables t ' +
                               'JOIN sys.schemas s ON t.schema_id = s.schema_id ' +
                               'WHERE t.name = @TableName;'

            -- Ejecutar la consulta para obtener el esquema
            EXEC sp_executesql @SchemaQuery, N'@TableName NVARCHAR(128), @SchemaName NVARCHAR(128) OUTPUT', @TableName, @SchemaName OUTPUT

            -- Generar la sentencia completa que incluye el cambio de contexto de base de datos y el esquema
            SET @FullSQL = 'USE [' + @DatabaseName + ']; ' + 
                           'ALTER INDEX [' + @IndexName + '] ON [' + @SchemaName + '].[' + @TableName + '] REBUILD WITH (ONLINE = ON);'

            -- Ejecutar la sentencia completa
            EXEC (@FullSQL)

            -- Registrar en la tabla de auditoría
            INSERT INTO IndexRebuildAudit (DatabaseName, TableName, IndexName, SchemaName, RebuildDateTime, Status)
            VALUES (@DatabaseName, @TableName, @IndexName, @SchemaName, GETDATE(), 'Success')
        END TRY
        BEGIN CATCH
            -- Registrar el error en la tabla de auditoría
            INSERT INTO IndexRebuildAudit (DatabaseName, TableName, IndexName, SchemaName, RebuildDateTime, Status, ErrorMessage)
            VALUES (@DatabaseName, @TableName, @IndexName, @SchemaName, GETDATE(), 'Error', ERROR_MESSAGE())
        END CATCH

        FETCH NEXT FROM @IndexCursor INTO @DatabaseName, @TableName, @IndexName
    END

    CLOSE @IndexCursor
    DEALLOCATE @IndexCursor
END
