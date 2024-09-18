/************************************************************************************************* 
 * Creado por: Daniel Israel
 * Fecha de creación: 01 de abril de 2024
 * Descripción: Script para Ofuscar decimal
 * GitHub: https://github.com/digarciab/dbtools
 *************************************************************************************************/
/*************************************************************************************************
  {
	   "DatabaseName": Nombre de la BD que se ofuscara. Ejemplo: "Gac", 
	   "TableSchema": Esquema de la tabla que contiene el campo a ofuscar. Ejemplo: "Sol", 
	   "TableName": Nombre de la tabla con el campo a ofuscar. Ejemplo: "ApplicationForm", 
	   "DecimalColumn": Nombre de la columna a ofuscar. Ejemplo: "Amount",
  }    
**************************************************************************************************/
DECLARE @json NVARCHAR(MAX) = '[
	{"DatabaseName": "", "TableSchema": "", "TableName": "", "DecimalColumn": ""}
]';

DECLARE @Salt NVARCHAR(128) = CAST(rand() as NVARCHAR(16));
DECLARE @FilterDatabaseName NVARCHAR(128) = ''; -- Cambiar a 'ALL' o NULL para todas las BDs o poner una BD especifica sin prefijo
DECLARE @PrefijoDestino NVARCHAR(128) = '';

DECLARE @paramsTable TABLE (
    DatabaseName NVARCHAR(128),
    TableSchema NVARCHAR(128),
    TableName NVARCHAR(128),
    DecimalColumn NVARCHAR(128)
);

-- Insertar en la tabla temporal con o sin filtro
INSERT INTO @paramsTable
SELECT 
    ISNULL(@PrefijoDestino, '') + DatabaseName,
    TableSchema,
    TableName,
    DecimalColumn
FROM OPENJSON(@json)
WITH (
        DatabaseName NVARCHAR(128) '$.DatabaseName',
        TableSchema NVARCHAR(128) '$.TableSchema',
        TableName NVARCHAR(128) '$.TableName',
        DecimalColumn NVARCHAR(128) '$.DecimalColumn'
    )
WHERE ISNULL(@FilterDatabaseName, 'ALL') = 'ALL' OR DatabaseName = @FilterDatabaseName;
	
DECLARE @DatabaseName NVARCHAR(128);
DECLARE @TableSchema NVARCHAR(128);
DECLARE @TableName NVARCHAR(128);
DECLARE @DecimalColumn NVARCHAR(128);
DECLARE @sql NVARCHAR(MAX);

DECLARE @ColumnExists BIT = 0;

DECLARE param_cursor CURSOR FOR
SELECT DatabaseName, TableSchema, TableName, DecimalColumn
FROM @paramsTable
WHERE EXISTS(SELECT 1 FROM sys.databases b WHERE b.name = DatabaseName);

OPEN param_cursor;

FETCH NEXT FROM param_cursor INTO @DatabaseName, @TableSchema, @TableName, @DecimalColumn;

WHILE @@FETCH_STATUS = 0
BEGIN

    -- Verificación de la existencia de la columna decimal
    SET @sql = '
        IF EXISTS (SELECT * FROM ' + QUOTENAME(@DatabaseName) + '.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ''' + @TableSchema + ''' AND TABLE_NAME = ''' + @TableName + ''' AND COLUMN_NAME = ''' + @DecimalColumn + ''' AND DATA_TYPE = ''decimal'')
        BEGIN
            SET @ColumnExists = 1;
        END';
    EXEC sp_executesql @sql, N'@ColumnExists BIT OUTPUT', @ColumnExists = @ColumnExists OUTPUT;
    IF @ColumnExists = 0
    BEGIN
        RAISERROR('El esquema, tabla, columna o tipo de dato especificado no existe.', 16, 1);
        FETCH NEXT FROM param_cursor INTO @DatabaseName, @TableSchema, @TableName, @DecimalColumn;
        CONTINUE;
    END

    -- Deshabilitar triggers si se especifica
    SET @sql = 'USE ' + QUOTENAME(@DatabaseName) + '; DISABLE TRIGGER ALL ON ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ';';
    EXEC sp_executesql @sql;

	-- Ofuscación de datos
	SET @sql = '
	USE ' + QUOTENAME(@DatabaseName) + ';
	WITH CTE AS (
		SELECT ' + QUOTENAME(@DecimalColumn) + ',
			   ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS RowNum
		FROM ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + '
	)
	UPDATE t
	SET ' + QUOTENAME(@DecimalColumn) + ' = ROUND(RAND(CHECKSUM(@Salt + CAST(NEWID() AS NVARCHAR(MAX)))) * 1000, 2) -- Cambia el 1000 al valor máximo deseado
	FROM ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ' t
	JOIN CTE ON t.' + QUOTENAME(@DecimalColumn) + ' = CTE.' + QUOTENAME(@DecimalColumn) + ';
	';    
    EXEC sp_executesql @sql, N'@Salt NVARCHAR(128)', @Salt = @Salt;

    -- Habilitar triggers si se deshabilitaron
    SET @sql = 'USE ' + QUOTENAME(@DatabaseName) + '; ENABLE TRIGGER ALL ON ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ';';
    EXEC sp_executesql @sql;

    PRINT 'Ofuscación completada exitosamente para la tabla ' + @TableSchema + '.' + @TableName + ' en la columna ' + @DecimalColumn + '.';

	FETCH NEXT FROM param_cursor INTO @DatabaseName, @TableSchema, @TableName, @DecimalColumn;

	Set @ColumnExists = 0;
END

CLOSE param_cursor;
DEALLOCATE param_cursor;
