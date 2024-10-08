USE [dbtools]
GO
/************************************************************************************************* 
 * StoredProcedure: [dbo].[InsertUserPermission]
 * Creado por: Daniel Israel
 * Fecha de creación: 01 de abril de 2024
 * Descripción: Procedimiento almacenado para agregar un permiso a una BD
 * GitHub: https://github.com/digarciab/dbtools
 *************************************************************************************************/
ALTER PROCEDURE [dbo].[InsertUserPermission]
    @Usuario NVARCHAR(128),
    @BaseDatos NVARCHAR(128),
    @TipoAcceso NVARCHAR(50),
    @ndias INT
AS
BEGIN
    BEGIN TRY
        -- Validar que el usuario sea un login válido
        IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @Usuario AND type IN ('S', 'U'))
        BEGIN
            RAISERROR('El usuario no es un login válido.', 16, 1);
            RETURN;
        END

        -- Validar que la base de datos exista
        IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @BaseDatos)
        BEGIN
            RAISERROR('La base de datos especificada no existe.', 16, 1);
            RETURN;
        END

        -- Validar el tipo de acceso
        IF @TipoAcceso NOT IN ('READONLY', 'VIEWONLY', 'FULL')
        BEGIN
            RAISERROR('El tipo de acceso especificado no es válido. Debe ser READONLY, VIEWONLY o FULL.', 16, 1);
            RETURN;
        END

        -- Calcular la fecha de inicio y la fecha de fin
        DECLARE @FechaInicio DATETIME = CAST(GETDATE() AS DATE);
        DECLARE @FechaFin DATETIME = DATEADD(DAY, @ndias, @FechaInicio);

        -- Insertar el nuevo registro
        INSERT INTO [dbo].[UserPermissions] ([Usuario], [BaseDatos], [TipoAcceso], [FechaInicio], [FechaFin])
        VALUES (@Usuario, @BaseDatos, @TipoAcceso, @FechaInicio, @FechaFin);

        -- Obtener el último registro insertado basado en los datos que acabas de insertar
        SELECT *
        FROM [dbo].[UserPermissions]
        WHERE [Usuario] = @Usuario AND [BaseDatos] = @BaseDatos AND [FechaInicio] = @FechaInicio AND [FechaFin] = @FechaFin;

        PRINT 'Registro insertado correctamente.';
    END TRY
    BEGIN CATCH
        -- Manejar el error y mostrar un mensaje de error
        PRINT 'Error al insertar el registro.';
        PRINT ERROR_MESSAGE();
    END CATCH
END
