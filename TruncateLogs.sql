/************************************************************************************************* 
 * Creado por: Daniel Israel
 * Fecha de creación: 01 de abril de 2024
 * Descripción: Script para truncar logs de BD
 * GitHub: https://github.com/digarciab/dbtools
 *************************************************************************************************/
-- Parámetro para especificar la base de datos a limpiar
DECLARE @DatabaseNameParam NVARCHAR(128) = '';  -- Reemplazar con el nombre de la base de datos
DECLARE @PrefijoDestino NVARCHAR(128) = '';
Set @DatabaseNameParam = ISNULL(@PrefijoDestino, '') + @DatabaseNameParam;

DECLARE @SchemaName NVARCHAR(128);
DECLARE @TableName NVARCHAR(128);
DECLARE @SQL NVARCHAR(MAX);
DECLARE @IdentityValue BIGINT;
DECLARE @IdentityColumn NVARCHAR(128);

-- Crear una tabla temporal para almacenar los resultados
CREATE TABLE #DatabaseTables (
    TableSchema NVARCHAR(128),
    TableName NVARCHAR(128),
    IdentityColumn NVARCHAR(128)
);

-- Obtener las tablas con columnas de tipo IDENTITY en la base de datos especificada
SET @SQL = 'USE [' + @DatabaseNameParam + ']; ' +
           'INSERT INTO #DatabaseTables (TableSchema, TableName, IdentityColumn) ' +
           'SELECT t.TABLE_SCHEMA, t.TABLE_NAME, c.COLUMN_NAME ' +
           'FROM INFORMATION_SCHEMA.TABLES t ' +
           'JOIN INFORMATION_SCHEMA.COLUMNS c ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME ' +
           'WHERE COLUMNPROPERTY(object_id(t.TABLE_SCHEMA + ''.'' + t.TABLE_NAME), c.COLUMN_NAME, ''IsIdentity'') = 1 ' +
           'AND EXISTS (SELECT 1 FROM dbatools.dbo.TableSearch ' +
           'WHERE dbatools.dbo.TableSearch.TableSchema COLLATE DATABASE_DEFAULT = t.TABLE_SCHEMA COLLATE DATABASE_DEFAULT ' +
           'AND dbatools.dbo.TableSearch.TableName COLLATE DATABASE_DEFAULT = t.TABLE_NAME COLLATE DATABASE_DEFAULT);';

-- Ejecutar la consulta para llenar la tabla temporal
EXEC sp_executesql @SQL;

-- Preparar la sentencia para truncar las tablas y restaurar el valor del IDENTITY
DECLARE truncate_cursor CURSOR FOR
SELECT TableSchema, TableName, IdentityColumn
FROM #DatabaseTables;

OPEN truncate_cursor;

FETCH NEXT FROM truncate_cursor INTO @SchemaName, @TableName, @IdentityColumn;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Obtener el valor máximo del IDENTITY antes de truncar la tabla
    SET @SQL = 'USE [' + @DatabaseNameParam + ']; ' +
               'SELECT @IdentityValue = ISNULL(MAX([' + @IdentityColumn + ']), 0) FROM [' + @SchemaName + '].[' + @TableName + '];';

    -- Ejecutar la consulta para obtener el valor máximo del IDENTITY
    EXEC sp_executesql @SQL, N'@IdentityValue BIGINT OUTPUT', @IdentityValue OUTPUT;

    -- Truncar la tabla
    SET @SQL = 'USE [' + @DatabaseNameParam + ']; ' +
               'TRUNCATE TABLE [' + @SchemaName + '].[' + @TableName + '];';

    -- Ejecutar la sentencia TRUNCATE TABLE
    EXEC sp_executesql @SQL;

    -- Restablecer el valor de la columna IDENTITY al valor anterior
    SET @SQL = 'USE [' + @DatabaseNameParam + ']; ' +
               'DBCC CHECKIDENT (''[' + @SchemaName + '].[' + @TableName + ']'', RESEED, ' + CAST(@IdentityValue AS NVARCHAR(MAX)) + ');';

    -- Ejecutar la sentencia DBCC CHECKIDENT para restaurar el IDENTITY
    EXEC sp_executesql @SQL;

    FETCH NEXT FROM truncate_cursor INTO @SchemaName, @TableName, @IdentityColumn;
END

CLOSE truncate_cursor;
DEALLOCATE truncate_cursor;

-- Limpiar la tabla temporal
DROP TABLE #DatabaseTables;
