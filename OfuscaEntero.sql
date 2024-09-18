/************************************************************************************************* 
 * Creado por: Daniel Israel
 * Fecha de creación: 01 de abril de 2024
 * Descripción: Script para ofuscar datos enteros
 * GitHub: https://github.com/digarciab/dbtools
 *************************************************************************************************/

/*************************************************************************************************
  {
	   "DatabaseName": Nombre de la BD que se ofuscara. Ejemplo: "Bai", 
	   "TableSchema": Esquema de la tabla que contiene el campo a ofuscar. Ejemplo: "Core", 
	   "TableName": Nombre de la tabla con el campo a ofuscar. Ejemplo: "RequestBaiApproval", 
	   "IntegerColumn": Nombre de la columna a ofuscar. Ejemplo: "ApprovalsOrder",
  }    
**************************************************************************************************/

DECLARE @json NVARCHAR(MAX) = '[
	{"DatabaseName": "", "TableSchema": "", "TableName": "", "IntegerColumn": ""}
]';

DECLARE @Salt NVARCHAR(128) = CAST(rand() as NVARCHAR(16));
DECLARE @FilterDatabaseName NVARCHAR(128) = ''; -- Cambiar a 'ALL' o NULL para ejecutar todos los parámetros sin filtro
DECLARE @PrefijoDestino NVARCHAR(128) = '';

DECLARE @paramsTable TABLE (
    DatabaseName NVARCHAR(128),
    TableSchema NVARCHAR(128),
    TableName NVARCHAR(128),
    IntegerColumn NVARCHAR(128)
);

-- Insertar en la tabla temporal con o sin filtro
INSERT INTO @paramsTable
SELECT 
    ISNULL(@PrefijoDestino, '') + DatabaseName,
    TableSchema,
    TableName,
    IntegerColumn
FROM OPENJSON(@json)
WITH (
        DatabaseName NVARCHAR(128) '$.DatabaseName',
        TableSchema NVARCHAR(128) '$.TableSchema',
        TableName NVARCHAR(128) '$.TableName',
        IntegerColumn NVARCHAR(128) '$.IntegerColumn'
    )
WHERE ISNULL(@FilterDatabaseName, 'ALL') = 'ALL' OR DatabaseName = @FilterDatabaseName;

DECLARE @DatabaseName NVARCHAR(128);
DECLARE @TableSchema NVARCHAR(128);
DECLARE @TableName NVARCHAR(128);
DECLARE @IntegerColumn NVARCHAR(128);
DECLARE @sql NVARCHAR(MAX);

DECLARE @ColumnExists BIT = 0;

DECLARE param_cursor CURSOR FOR
SELECT DatabaseName, TableSchema, TableName, IntegerColumn
FROM @paramsTable
WHERE EXISTS(SELECT 1 FROM sys.databases b WHERE b.name = DatabaseName);

OPEN param_cursor;

FETCH NEXT FROM param_cursor INTO @DatabaseName, @TableSchema, @TableName, @IntegerColumn;

WHILE @@FETCH_STATUS = 0
BEGIN

    -- Verificación de la existencia de la columna entera
    SET @sql = '
        IF EXISTS (SELECT * FROM ' + QUOTENAME(@DatabaseName) + '.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ''' + @TableSchema + ''' AND TABLE_NAME = ''' + @TableName + ''' AND COLUMN_NAME = ''' + @IntegerColumn + ''' AND DATA_TYPE = ''int'')
        BEGIN
            SET @ColumnExists = 1;
        END';
    EXEC sp_executesql @sql, N'@ColumnExists BIT OUTPUT', @ColumnExists = @ColumnExists OUTPUT;
    IF @ColumnExists = 0
    BEGIN
        RAISERROR('El esquema, tabla, columna o tipo de dato especificado no existe.', 16, 1);
        FETCH NEXT FROM param_cursor INTO @DatabaseName, @TableSchema, @TableName, @IntegerColumn;
        CONTINUE;
    END

    -- Deshabilitar triggers si se especifica
    SET @sql = 'USE ' + QUOTENAME(@DatabaseName) + '; DISABLE TRIGGER ALL ON ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ';';
    EXEC sp_executesql @sql;

    -- Ofuscación de datos
    SET @sql = '
    USE ' + QUOTENAME(@DatabaseName) + ';
    UPDATE t
    SET ' + QUOTENAME(@IntegerColumn) + ' = ABS(CHECKSUM(@Salt + CAST(NEWID() AS NVARCHAR(MAX)))) % 1000 -- Cambia el 1000 al valor máximo deseado
    FROM ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ' t;';
    
    EXEC sp_executesql @sql, N'@Salt NVARCHAR(128)', @Salt = @Salt;

    -- Habilitar triggers si se deshabilitaron
    SET @sql = 'USE ' + QUOTENAME(@DatabaseName) + '; ENABLE TRIGGER ALL ON ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ';';
    EXEC sp_executesql @sql;

    PRINT 'Obfuscación completada exitosamente para la tabla ' + @TableSchema + '.' + @TableName + ' en la columna ' + @IntegerColumn + '.';

    FETCH NEXT FROM param_cursor INTO @DatabaseName, @TableSchema, @TableName, @IntegerColumn;

	SET @ColumnExists = 0;
END

CLOSE param_cursor;
DEALLOCATE param_cursor;
