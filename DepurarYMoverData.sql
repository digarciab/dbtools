USE [dbtools]
GO
/************************************************************************************************* 
 * StoredProcedure: [dbo].[DepurarYMoverData]
 * Creado por: Daniel Israel
 * Fecha de creación: 01 de abril de 2024
 * Descripción: Procedimiento almacenado para depurar o mover data hacia bd historica
 * GitHub: https://github.com/digarciab/dbtools
 *************************************************************************************************/
ALTER PROCEDURE [dbo].[DepurarYMoverData]
    @OrigenBD NVARCHAR(255),
    @OrigenEsquema NVARCHAR(255),
    @OrigenTabla NVARCHAR(255),
    @ColumnaFiltro NVARCHAR(255),
    @DiasARetener INT,
    @Operacion NVARCHAR(10), -- Puede ser 'DELETE' o 'MOVE'
    @DestinoBD NVARCHAR(255) = NULL -- Solo necesario si la operación es 'MOVE'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TamanoTablaMB DECIMAL(18, 2);
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @InsertCount INT;
    DECLARE @DeleteCount INT;
    DECLARE @IdentityColumns NVARCHAR(MAX);
    DECLARE @ColumnList NVARCHAR(MAX);
    DECLARE @SelectColumns NVARCHAR(MAX);
    DECLARE @DestinoSchema NVARCHAR(255);
    DECLARE @DestinoTabla NVARCHAR(255);
    DECLARE @BatchSize INT = 1000;
    DECLARE @InsertedBatch INT;
    DECLARE @ErrorFlag BIT = 0; -- Flag para controlar rollback y salida del bucle
    DECLARE @PKColumns NVARCHAR(MAX);
    DECLARE @PKColumnsList NVARCHAR(MAX);

    -- Variables para manejo de errores
    DECLARE @ErrorMessage NVARCHAR(4000);
    DECLARE @ErrorSeverity INT;
    DECLARE @ErrorState INT;

    -- Crear una tabla temporal para almacenar contadores
    CREATE TABLE #Counters (CountValue INT);

    -- Obtener tamaño de la tabla en MB
    SET @SQL = '
        USE ' + QUOTENAME(@OrigenBD) + ';
        SELECT @TamanoTablaMB = SUM(reserved_page_count) * 8.0 / 1024 
        FROM sys.dm_db_partition_stats 
        WHERE object_id = OBJECT_ID(''' + QUOTENAME(@OrigenEsquema) + '.' + QUOTENAME(@OrigenTabla) + ''');';
    EXEC sp_executesql @SQL, N'@TamanoTablaMB DECIMAL(18,2) OUTPUT', @TamanoTablaMB OUTPUT;

    IF @TamanoTablaMB > 0
    BEGIN
        -- Obtener la lista de columnas de la clave primaria de la tabla origen
        SET @SQL = '
            USE ' + QUOTENAME(@OrigenBD) + ';
            DECLARE @PKColumnsTemp NVARCHAR(MAX);
            SELECT @PKColumnsTemp = COALESCE(@PKColumnsTemp + '','' , '''') + COLUMN_NAME
            FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
            WHERE TABLE_SCHEMA = ''' + @OrigenEsquema + '''
                AND TABLE_NAME = ''' + @OrigenTabla + '''
                AND CONSTRAINT_NAME = (
                    SELECT CONSTRAINT_NAME
                    FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
                    WHERE TABLE_SCHEMA = ''' + @OrigenEsquema + '''
                      AND TABLE_NAME = ''' + @OrigenTabla + '''
                      AND CONSTRAINT_TYPE = ''PRIMARY KEY''
                )
            ORDER BY ORDINAL_POSITION;
            SELECT @PKColumns = @PKColumnsTemp;';
        EXEC sp_executesql @SQL, N'@PKColumns NVARCHAR(MAX) OUTPUT', @PKColumns OUTPUT;

        IF @PKColumns IS NULL
        BEGIN
            RAISERROR('No se encontró una clave primaria para la tabla origen.', 16, 1);
            RETURN;
        END

        -- Crear la lista de columnas de la clave primaria separadas por comas
        SET @PKColumnsList = REPLACE(@PKColumns, ',', '], [');
        SET @PKColumnsList = '[' + @PKColumnsList + ']';

        IF @Operacion = 'MOVE'
        BEGIN
            SET @DestinoSchema = @OrigenBD;
            SET @DestinoTabla = @OrigenEsquema + '_' + @OrigenTabla;

            -- Crear el esquema en la base de datos destino si no existe
            SET @SQL = '
                USE ' + QUOTENAME(@DestinoBD) + ';
                IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''' + @DestinoSchema + ''')
                BEGIN
                    EXEC(''CREATE SCHEMA ' + QUOTENAME(@DestinoSchema) + ''');
                END
                IF NOT EXISTS (SELECT 1 FROM sys.tables t
                                INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
                                WHERE s.name = ''' + @DestinoSchema + ''' AND t.name = ''' + @DestinoTabla + ''')
                BEGIN
                    EXEC(''SELECT * INTO ' + QUOTENAME(@DestinoSchema) + '.' + QUOTENAME(@DestinoTabla) + '
                          FROM ' + QUOTENAME(@OrigenBD) + '.' + QUOTENAME(@OrigenEsquema) + '.' + QUOTENAME(@OrigenTabla) + '
                          WHERE 1 = 0'');
                END';
            EXEC sp_executesql @SQL;

            -- Obtener las columnas IDENTITY de la tabla origen
            SET @IdentityColumns = NULL;
            SET @SQL = '
                USE ' + QUOTENAME(@OrigenBD) + ';
                SELECT @IdentityColumns = COALESCE(@IdentityColumns + '','', '''') + QUOTENAME(column_name)
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = ''' + @OrigenEsquema + ''' 
                  AND TABLE_NAME = ''' + @OrigenTabla + ''' 
                  AND COLUMNPROPERTY(OBJECT_ID(TABLE_SCHEMA + ''.'' + TABLE_NAME), column_name, ''IsIdentity'') = 1;';
            EXEC sp_executesql @SQL, N'@IdentityColumns NVARCHAR(MAX) OUTPUT', @IdentityColumns OUTPUT;

            -- Obtener la lista de columnas de la tabla origen
            SET @ColumnList = NULL;
            SET @SelectColumns = NULL;
            SET @SQL = '
                USE ' + QUOTENAME(@OrigenBD) + ';
                SELECT @ColumnList = COALESCE(@ColumnList + '','', '''') + QUOTENAME(column_name),
                       @SelectColumns = COALESCE(@SelectColumns + '','', '''') + QUOTENAME(column_name)
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = ''' + @OrigenEsquema + ''' 
                  AND TABLE_NAME = ''' + @OrigenTabla + ''' 
                ORDER BY ordinal_position;';
            EXEC sp_executesql @SQL, N'@ColumnList NVARCHAR(MAX) OUTPUT, @SelectColumns NVARCHAR(MAX) OUTPUT', @ColumnList OUTPUT, @SelectColumns OUTPUT;

            -- Preparar las consultas para insertar los datos en la tabla destino
            IF @IdentityColumns IS NOT NULL AND @IdentityColumns <> ''
            BEGIN
                -- Insertar los registros en lotes y manejar IDENTITY_INSERT en la tabla destino
                WHILE (1 = 1)
                BEGIN
                    BEGIN TRY
                        BEGIN TRANSACTION;
                            -- Insertar el lote en la tabla destino
                            SET @SQL = 'USE ' + QUOTENAME(@OrigenBD) + ';
                                        SET IDENTITY_INSERT ' + QUOTENAME(@DestinoBD) + '.' + QUOTENAME(@DestinoSchema) + '.' + QUOTENAME(@DestinoTabla) + ' ON;
                                        INSERT INTO ' + QUOTENAME(@DestinoBD) + '.' + QUOTENAME(@DestinoSchema) + '.' + QUOTENAME(@DestinoTabla) + ' (' + @ColumnList + ')
                                        SELECT TOP (' + CAST(@BatchSize AS NVARCHAR(10)) + ') ' + @SelectColumns + '
                                        FROM ' + QUOTENAME(@OrigenEsquema) + '.' + QUOTENAME(@OrigenTabla) + '
                                        WHERE [' + @ColumnaFiltro + '] < DATEADD(day, -' + CAST(@DiasARetener AS NVARCHAR(10)) + ', GETDATE())
										ORDER BY ' + @PKColumnsList + ';
                                        SET IDENTITY_INSERT ' + QUOTENAME(@DestinoBD) + '.' + QUOTENAME(@DestinoSchema) + '.' + QUOTENAME(@DestinoTabla) + ' OFF;';
                            EXEC sp_executesql @SQL;

                            -- Verificar el número de registros insertados
                            SET @SQL = 'USE ' + QUOTENAME(@DestinoBD) + ';
                                        INSERT INTO #Counters (CountValue)
                                        SELECT COUNT(*)
                                        FROM ' + QUOTENAME(@DestinoSchema) + '.' + QUOTENAME(@DestinoTabla) + '
                                        WHERE (' + @PKColumns + ') IN (
                                            SELECT TOP (' + CAST(@BatchSize AS NVARCHAR(10)) + ') (' + @PKColumns + ')
                                            FROM ' + QUOTENAME(@OrigenBD) + '.' + QUOTENAME(@OrigenEsquema) + '.' + QUOTENAME(@OrigenTabla) + '
                                            WHERE [' + @ColumnaFiltro + '] < DATEADD(day, -' + CAST(@DiasARetener AS NVARCHAR(10)) + ', GETDATE())
                                            ORDER BY ' + @PKColumns + '
                                        );';
                            EXEC sp_executesql @SQL;

                            SELECT @InsertedBatch = CountValue FROM #Counters;
                            DELETE FROM #Counters;
							
                            -- Verificar si el lote completo fue insertado
							IF @InsertedBatch > 0 
                            BEGIN
					            -- Eliminar los registros del lote de la tabla origen
								SET @SQL = 'USE ' + QUOTENAME(@OrigenBD) + ';
											DELETE FROM ' + QUOTENAME(@OrigenEsquema) + '.' + QUOTENAME(@OrigenTabla) + '
											WHERE ' + @PKColumnsList + ' IN (
												SELECT TOP (' + CAST(@BatchSize AS NVARCHAR(10)) + ') ' + @PKColumnsList + '
												FROM ' + QUOTENAME(@OrigenEsquema) + '.' + QUOTENAME(@OrigenTabla) + '
												WHERE [' + @ColumnaFiltro + '] < DATEADD(day, -' + CAST(@DiasARetener AS NVARCHAR(10)) + ', GETDATE())
												ORDER BY ' + @PKColumnsList + '
											);';								
								EXEC sp_executesql @SQL;
                            END
                            ELSE
                            BEGIN
                                SET @ErrorFlag = 1; -- Marcar para salir del bucle
                                ROLLBACK TRANSACTION;
                                BREAK;
                            END

                            COMMIT TRANSACTION;
                    END TRY
                    BEGIN CATCH
                        -- Manejo de errores
                        ROLLBACK TRANSACTION;
                        SELECT 
                            @ErrorMessage = ERROR_MESSAGE(),
                            @ErrorSeverity = ERROR_SEVERITY(),
                            @ErrorState = ERROR_STATE();
                        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
                        SET @ErrorFlag = 1; -- Marcar para salir del bucle
                        BREAK;
                    END CATCH;

                    IF @ErrorFlag = 1
                        BREAK;
                END
            END
            ELSE
            BEGIN
                -- Insertar sin IDENTITY_INSERT
                WHILE (1 = 1)
                BEGIN
                    BEGIN TRY
                        BEGIN TRANSACTION;
                            -- Insertar el lote en la tabla destino
                            SET @SQL = 'USE ' + QUOTENAME(@OrigenBD) + ';
                                        INSERT INTO ' + QUOTENAME(@DestinoBD) + '.' + QUOTENAME(@DestinoSchema) + '.' + QUOTENAME(@DestinoTabla) + ' (' + @ColumnList + ')
                                        SELECT TOP (' + CAST(@BatchSize AS NVARCHAR(10)) + ') ' + @SelectColumns + '
                                        FROM ' + QUOTENAME(@OrigenEsquema) + '.' + QUOTENAME(@OrigenTabla) + '
                                        WHERE [' + @ColumnaFiltro + '] < DATEADD(day, -' + CAST(@DiasARetener AS NVARCHAR(10)) + ', GETDATE())
										ORDER BY ' + @PKColumnsList + ';';
                            EXEC sp_executesql @SQL;

                            -- Verificar el número de registros insertados
                            SET @SQL = 'USE ' + QUOTENAME(@DestinoBD) + ';
                                        INSERT INTO #Counters (CountValue)
                                        SELECT COUNT(*)
                                        FROM ' + QUOTENAME(@DestinoSchema) + '.' + QUOTENAME(@DestinoTabla) + '
                                        WHERE (' + @PKColumns + ') IN (
                                            SELECT TOP (' + CAST(@BatchSize AS NVARCHAR(10)) + ') (' + @PKColumns + ')
                                            FROM ' + QUOTENAME(@OrigenBD) + '.' + QUOTENAME(@OrigenEsquema) + '.' + QUOTENAME(@OrigenTabla) + '
                                            WHERE [' + @ColumnaFiltro + '] < DATEADD(day, -' + CAST(@DiasARetener AS NVARCHAR(10)) + ', GETDATE())
                                            ORDER BY ' + @PKColumns + '
                                        );';
                            EXEC sp_executesql @SQL;

                            SELECT @InsertedBatch = CountValue FROM #Counters;
                            DELETE FROM #Counters;

                            IF @InsertedBatch > 0
                            BEGIN
					            -- Eliminar los registros del lote de la tabla origen
								SET @SQL = 'USE ' + QUOTENAME(@OrigenBD) + ';
											DELETE FROM ' + QUOTENAME(@OrigenEsquema) + '.' + QUOTENAME(@OrigenTabla) + '
											WHERE [' + @PKColumnsList + '] IN (
												SELECT TOP (' + CAST(@BatchSize AS NVARCHAR(10)) + ') [' + @PKColumnsList + ']
												FROM ' + QUOTENAME(@OrigenEsquema) + '.' + QUOTENAME(@OrigenTabla) + '
												WHERE [' + @ColumnaFiltro + '] < DATEADD(day, -' + CAST(@DiasARetener AS NVARCHAR(10)) + ', GETDATE())
												ORDER BY [' + @PKColumnsList + ']
											);';
								EXEC sp_executesql @SQL;
                            END
                            ELSE
                            BEGIN
                                SET @ErrorFlag = 1; -- Marcar para salir del bucle
                                ROLLBACK TRANSACTION;
                                BREAK;
                            END

                            COMMIT TRANSACTION;
                    END TRY
                    BEGIN CATCH
                        -- Manejo de errores
                        ROLLBACK TRANSACTION;
                        SELECT 
                            @ErrorMessage = ERROR_MESSAGE(),
                            @ErrorSeverity = ERROR_SEVERITY(),
                            @ErrorState = ERROR_STATE();
                        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
                        SET @ErrorFlag = 1; -- Marcar para salir del bucle
                        BREAK;
                    END CATCH;

                    IF @ErrorFlag = 1
                        BREAK;
                END
            END
        END
        ELSE IF @Operacion = 'DELETE'
        BEGIN
            -- Eliminación de datos
            WHILE (1 = 1)
            BEGIN
                BEGIN TRY
                    BEGIN TRANSACTION;
                        SET @SQL = 'USE ' + QUOTENAME(@OrigenBD) + ';
                                    DELETE TOP (' + CAST(@BatchSize AS NVARCHAR(10)) + ') 
                                    FROM ' + QUOTENAME(@OrigenEsquema) + '.' + QUOTENAME(@OrigenTabla) + '
                                    WHERE [' + @ColumnaFiltro + '] < DATEADD(day, -' + CAST(@DiasARetener AS NVARCHAR(10)) + ', GETDATE());';
                        EXEC sp_executesql @SQL;

                        -- Contar los registros restantes que cumplen la condición
                        SET @SQL = 'USE ' + QUOTENAME(@OrigenBD) + ';
                                    INSERT INTO #Counters (CountValue)
                                    SELECT COUNT(*)
                                    FROM ' + QUOTENAME(@OrigenEsquema) + '.' + QUOTENAME(@OrigenTabla) + '
                                    WHERE [' + @ColumnaFiltro + '] < DATEADD(day, -' + CAST(@DiasARetener AS NVARCHAR(10)) + ', GETDATE());';
                        EXEC sp_executesql @SQL;

                        SELECT @DeleteCount = CountValue FROM #Counters;
                        DELETE FROM #Counters;

                        IF @DeleteCount = 0
                        BEGIN
                            COMMIT TRANSACTION;
                            BREAK;
                        END

                        COMMIT TRANSACTION;
                END TRY
                BEGIN CATCH
                    -- Manejo de errores
                    ROLLBACK TRANSACTION;
                    SELECT 
                        @ErrorMessage = ERROR_MESSAGE(),
                        @ErrorSeverity = ERROR_SEVERITY(),
                        @ErrorState = ERROR_STATE();
                    RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
                    BREAK;
                END CATCH;
            END
        END
        ELSE
        BEGIN
            RAISERROR('Operación no reconocida. Use ''DELETE'' o ''MOVE''.', 16, 1);
        END
    END
    ELSE
    BEGIN
        PRINT 'Tabla vacia o No se pudo obtener su tamaño.';
    END

    DROP TABLE #Counters;
END;
