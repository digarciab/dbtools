/************************************************************************************************* 
 * Creado por: Daniel Israel
 * Fecha de creación: 01 de abril de 2024
 * Descripción: Script para ofuscar Alfanumerico
 * GitHub: https://github.com/digarciab/dbtools
 *************************************************************************************************/
/*************************************************************************************************
  {
	   "DatabaseName": Nombre de la BD que se ofuscara. Ejemplo: "Bai15", 
	   "TableSchema": Esquema de la tabla que contiene el campo a ofuscar. Ejemplo: "Core", 
	   "TableName": Nombre de la tabla con el campo a ofuscar. Ejemplo: "RequestBai", 
	   "AlphaNumericColumn": Nombre de la columna a ofuscar. Ejemplo: "DescriptionRequirement"
  }    
**************************************************************************************************/

DECLARE @json NVARCHAR(MAX) = '[
	{"DatabaseName": "", "TableSchema": "", "TableName": "", "AlphaNumericColumn": ""}
]';

DECLARE @Salt NVARCHAR(128) = CAST(rand() as NVARCHAR(16));
DECLARE @FilterDatabaseName NVARCHAR(128) = ''; -- Cambiar a 'ALL' o NULL para todas las BD o poner una especifica sin prefijo
DECLARE @PrefijoDestino NVARCHAR(128) = '';

DECLARE @paramsTable TABLE (
    DatabaseName NVARCHAR(128),
    TableSchema NVARCHAR(128),
    TableName NVARCHAR(128),
    AlphaNumericColumn NVARCHAR(128)
);

-- Insertar en la tabla temporal con o sin filtro
INSERT INTO @paramsTable
SELECT 
    ISNULL(@PrefijoDestino, '') + DatabaseName,
    TableSchema,
    TableName,
    AlphaNumericColumn
FROM OPENJSON(@json)
WITH (
    DatabaseName NVARCHAR(128) '$.DatabaseName',
    TableSchema NVARCHAR(128) '$.TableSchema',
    TableName NVARCHAR(128) '$.TableName',
    AlphaNumericColumn NVARCHAR(128) '$.AlphaNumericColumn'
)
WHERE ISNULL(@FilterDatabaseName, 'ALL') = 'ALL' OR DatabaseName = @FilterDatabaseName;

DECLARE @DatabaseName NVARCHAR(128);
DECLARE @TableSchema NVARCHAR(128);
DECLARE @TableName NVARCHAR(128);
DECLARE @AlphaNumericColumn NVARCHAR(128);
DECLARE @sql NVARCHAR(MAX);

DECLARE @ColumnExists BIT = 0;
DECLARE @PrimaryKeyColumns NVARCHAR(MAX);
DECLARE @PrimaryKeyConditions NVARCHAR(MAX) = '';

DECLARE param_cursor CURSOR FOR
SELECT DatabaseName, TableSchema, TableName, AlphaNumericColumn
FROM @paramsTable
WHERE EXISTS(SELECT 1 FROM sys.databases b WHERE b.name = DatabaseName);

OPEN param_cursor;

FETCH NEXT FROM param_cursor INTO @DatabaseName, @TableSchema, @TableName, @AlphaNumericColumn;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Verificación de la existencia de la columna alfanumérica
    SET @sql = '
        IF EXISTS (SELECT * FROM ' + QUOTENAME(@DatabaseName) + '.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ''' + @TableSchema + ''' AND TABLE_NAME = ''' + @TableName + ''' AND COLUMN_NAME = ''' + @AlphaNumericColumn + ''')
        BEGIN
            SET @ColumnExists = 1;
        END';
    EXEC sp_executesql @sql, N'@ColumnExists BIT OUTPUT', @ColumnExists = @ColumnExists OUTPUT;
    IF @ColumnExists = 0
    BEGIN
        RAISERROR('El esquema, tabla, columna o tipo de dato especificado no existe.', 16, 1);
        FETCH NEXT FROM param_cursor INTO @DatabaseName, @TableSchema, @TableName, @AlphaNumericColumn;
        CONTINUE;
    END

    -- Obtener los nombres de las columnas de clave primaria    
    SET @sql = '
        USE ' + QUOTENAME(@DatabaseName) + ';

        SELECT @PrimaryKeyColumns = COALESCE(@PrimaryKeyColumns + '', '', '''') + QUOTENAME(c.name),
               @PrimaryKeyConditions = @PrimaryKeyConditions + IIF(@PrimaryKeyConditions = '''', '''', '' AND '') + ''t.'' + QUOTENAME(c.name) + '' = O.'' + QUOTENAME(c.name)
        FROM sys.indexes AS i
        INNER JOIN sys.index_columns AS ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
        INNER JOIN sys.columns AS c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        WHERE i.is_primary_key = 1
        AND ic.object_id = OBJECT_ID(@TableSchema + ''.'' + @TableName);
    ';
    EXEC sp_executesql @sql, 
        N'@TableName NVARCHAR(128), @TableSchema NVARCHAR(128), @PrimaryKeyColumns NVARCHAR(MAX) OUTPUT, @PrimaryKeyConditions NVARCHAR(MAX) OUTPUT', 
        @TableName, 
        @TableSchema, 
        @PrimaryKeyColumns = @PrimaryKeyColumns OUTPUT, 
        @PrimaryKeyConditions = @PrimaryKeyConditions OUTPUT;
    IF @PrimaryKeyColumns IS NULL
    BEGIN
        RAISERROR('No se encontró una clave primaria para la tabla especificada.', 16, 1);
        FETCH NEXT FROM param_cursor INTO @DatabaseName, @TableSchema, @TableName, @AlphaNumericColumn;
        CONTINUE;
    END

    -- Deshabilitar triggers si se especifica
    SET @sql = 'USE ' + QUOTENAME(@DatabaseName) + '; DISABLE TRIGGER ALL ON ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ';';
    EXEC sp_executesql @sql;
    
    -- Ofuscación de datos
    SET @sql = '
    USE ' + QUOTENAME(@DatabaseName) + ';
    WITH CharList AS (
        SELECT
            ' + @PrimaryKeyColumns + ',
            SUBSTRING(t.' + QUOTENAME(@AlphaNumericColumn) + ', v.number, 1) AS CharValue,
            v.number AS CharPosition
        FROM ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ' t
        JOIN master..spt_values v ON v.type = ''P''
        WHERE v.number BETWEEN 1 AND LEN(t.' + QUOTENAME(@AlphaNumericColumn) + ')
    )
    , ObfuscatedChars AS (
        SELECT
            ' + @PrimaryKeyColumns + ',
            CHAR(
                CASE
                    WHEN CharValue = '' '' THEN ASCII(CharValue)
                    WHEN CharValue LIKE ''[0-9]'' THEN 48 + ABS(CHECKSUM(@Salt+CAST(NEWID() AS NVARCHAR(MAX)))) % 10
                    WHEN CharValue LIKE ''[A-Z]'' THEN 65 + ABS(CHECKSUM(@Salt+CAST(NEWID() AS NVARCHAR(MAX)))) % 26
                    WHEN CharValue LIKE ''[a-z]'' THEN 97 + ABS(CHECKSUM(@Salt+CAST(NEWID() AS NVARCHAR(MAX)))) % 26
                    WHEN CharValue IN (''.'', ''@'', ''-'', ''/'', ''\\'') THEN ASCII(CharValue)
                    ELSE 33 + ABS(CHECKSUM(@Salt+CAST(NEWID() AS NVARCHAR(MAX)))) % 15
                END
            ) AS ObfuscatedChar,
            CharPosition
        FROM CharList
    )
    , ObfuscatedStrings AS (
        SELECT 
            ' + @PrimaryKeyColumns + ',
            (
                SELECT ObfuscatedChar + ''''
                FROM ObfuscatedChars AS t
                WHERE ' + @PrimaryKeyConditions + '
                ORDER BY CharPosition
                FOR XML PATH(''''), TYPE
            ).value(''.'', ''NVARCHAR(MAX)'') AS ObfuscatedString
        FROM ObfuscatedChars AS O
        GROUP BY ' + @PrimaryKeyColumns + '
    )
    UPDATE t
    SET ' + QUOTENAME(@AlphaNumericColumn) + ' = O.ObfuscatedString
    FROM ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ' t
    JOIN ObfuscatedStrings O ON ' + @PrimaryKeyConditions + ';';

	--PRINT @sql;
    EXEC sp_executesql @sql, N'@Salt NVARCHAR(128)', @Salt = @Salt;

    -- Habilitar triggers si se deshabilitaron
    SET @sql = 'USE ' + QUOTENAME(@DatabaseName) + '; ENABLE TRIGGER ALL ON ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ';';
    EXEC sp_executesql @sql;
	
	PRINT 'Obfuscación completada exitosamente para la tabla ' + @TableSchema + '.' + @TableName + ' en la columna ' + @AlphaNumericColumn + '.';
    
	FETCH NEXT FROM param_cursor INTO @DatabaseName, @TableSchema, @TableName, @AlphaNumericColumn;

    -- Reiniciar Variables para la próxima tabla
    SET @PrimaryKeyColumns = NULL;
    SET @ColumnExists = 0;
    SET @PrimaryKeyConditions = '';

END

CLOSE param_cursor;
DEALLOCATE param_cursor;