USE [dbtools]
GO
/************************************************************************************************* 
 * StoredProcedure: [dbo].[GestionaPermisosBaseDatos]
 * Creado por: Daniel Israel
 * Fecha de creación: 01 de abril de 2024
 * Descripción: Procedimiento almacenado para gestionar los permisos de usuario a la BD
 * GitHub: https://github.com/digarciab/dbtools
 *************************************************************************************************/
ALTER PROCEDURE [dbo].[GestionaPermisosBaseDatos]
AS
BEGIN
    DECLARE @sql NVARCHAR(MAX);
    DECLARE @Usuario NVARCHAR(128);
    DECLARE @BaseDatos NVARCHAR(128);
    DECLARE @TipoAcceso NVARCHAR(50);
    DECLARE @FechaInicio DATETIME;
    DECLARE @FechaFin DATETIME;
    DECLARE @Hoy DATETIME;
    DECLARE @Accion NVARCHAR(10);
    DECLARE @ErrorMessage NVARCHAR(4000);

    -- Variables para recorrer la tabla
    DECLARE cur CURSOR FOR
    SELECT Usuario, BaseDatos, TipoAcceso, FechaInicio, FechaFin
    FROM UserPermissions;

    BEGIN TRY
        OPEN cur;
        FETCH NEXT FROM cur INTO @Usuario, @BaseDatos, @TipoAcceso, @FechaInicio, @FechaFin;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- Determinar la acción a realizar (OTORGAR o REVOCAR) dependiendo de la fecha actual
            SET @Hoy = GETDATE();
            IF @Hoy BETWEEN @FechaInicio AND @FechaFin
            BEGIN
                SET @Accion = 'OTORGAR';
            END
            ELSE
            BEGIN
                SET @Accion = 'REVOCAR';
            END

            -- Ejecutar acciones según el tipo de acceso
            IF @TipoAcceso = 'READALL'
            BEGIN
                -- Otorgar o revocar permisos de servidor para leer todas las bases de datos
                IF @Accion = 'OTORGAR'
                BEGIN
                    SET @sql = 'ALTER SERVER ROLE [readonly_role] ADD MEMBER ' + QUOTENAME(@Usuario) + ';';
                END
                ELSE IF @Accion = 'REVOCAR'
                BEGIN
                    SET @sql = 'ALTER SERVER ROLE [readonly_role] DROP MEMBER ' + QUOTENAME(@Usuario) + ';';
                END
            END
            ELSE
            BEGIN
                -- Verificar y crear el usuario de base de datos si no existe, solo si el tipo de acceso no es READALL
                SET @sql = 'USE ' + QUOTENAME(@BaseDatos) + ';
                            IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = ' + QUOTENAME(@Usuario, '''') + ')
                            BEGIN
                                CREATE USER ' + QUOTENAME(@Usuario) + ' FOR LOGIN ' + QUOTENAME(@Usuario) + ';
                            END;';

                BEGIN TRY
                    -- Ejecutar la consulta para crear el usuario si no existe
                    EXEC sp_executesql @sql;
                END TRY
                BEGIN CATCH
                    -- Generar un mensaje de error personalizado si falla la creación del usuario
                    SET @ErrorMessage = ERROR_MESSAGE();
                    RAISERROR('Error al crear el usuario en la base de datos: %s', 16, 1, @ErrorMessage);
                    FETCH NEXT FROM cur INTO @Usuario, @BaseDatos, @TipoAcceso, @FechaInicio, @FechaFin;
                    CONTINUE; -- Pasar al siguiente registro
                END CATCH

                -- Construir la sentencia SQL según la acción determinada
                IF @Accion = 'OTORGAR'
                BEGIN
                    IF @TipoAcceso = 'READONLY'
                    BEGIN
                        SET @sql = 'USE ' + QUOTENAME(@BaseDatos) + ';
                                    ALTER ROLE db_datareader ADD MEMBER ' + QUOTENAME(@Usuario) + ';';
                    END
                    ELSE IF @TipoAcceso = 'FULL'
                    BEGIN
                        SET @sql = 'USE ' + QUOTENAME(@BaseDatos) + ';
                                    ALTER ROLE db_datareader ADD MEMBER ' + QUOTENAME(@Usuario) + ';
                                    ALTER ROLE db_ddladmin ADD MEMBER ' + QUOTENAME(@Usuario) + ';
                                    ALTER ROLE db_datawriter ADD MEMBER ' + QUOTENAME(@Usuario) + ';';
                    END
                    ELSE IF @TipoAcceso = 'VIEWONLY'
                    BEGIN
                        SET @sql = 'USE ' + QUOTENAME(@BaseDatos) + ';
                                    ALTER ROLE db_datareader ADD MEMBER ' + QUOTENAME(@Usuario) + ';
                                    GRANT VIEW DEFINITION TO ' + QUOTENAME(@Usuario) + ';';
                    END
                END
                ELSE IF @Accion = 'REVOCAR'
                BEGIN
                    SET @sql = 'USE ' + QUOTENAME(@BaseDatos) + ';
                                IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = ' + QUOTENAME(@Usuario, '''') + ')
                                BEGIN 
                                    IF IS_ROLEMEMBER(''db_datareader'', ' + QUOTENAME(@Usuario, '''') + ') = 1 
                                    BEGIN 
                                        ALTER ROLE db_datareader DROP MEMBER ' + QUOTENAME(@Usuario) + ';
                                    END;
                                    IF IS_ROLEMEMBER(''db_ddladmin'', ' + QUOTENAME(@Usuario, '''') + ') = 1 
                                    BEGIN 
                                        ALTER ROLE db_ddladmin DROP MEMBER ' + QUOTENAME(@Usuario) + ';
                                    END;
                                    IF IS_ROLEMEMBER(''db_datawriter'', ' + QUOTENAME(@Usuario, '''') + ') = 1 
                                    BEGIN 
                                        ALTER ROLE db_datawriter DROP MEMBER ' + QUOTENAME(@Usuario) + ';
                                    END;
                                    -- Revocar permiso de VIEW DEFINITION
                                    REVOKE VIEW DEFINITION FROM ' + QUOTENAME(@Usuario) + ';
                                END;';
                END
            END

            BEGIN TRY
                -- Ejecutar la consulta para otorgar o revocar roles
                EXEC sp_executesql @sql;
            END TRY
            BEGIN CATCH
                -- Generar un mensaje de error personalizado si falla la acción de otorgar o revocar roles
                SET @ErrorMessage = ERROR_MESSAGE();
                RAISERROR('Error al ejecutar el procedimiento: %s', 16, 1, @ErrorMessage);
            END CATCH

            FETCH NEXT FROM cur INTO @Usuario, @BaseDatos, @TipoAcceso, @FechaInicio, @FechaFin;
        END

        CLOSE cur;
        DEALLOCATE cur;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('global', 'cur') >= -1
        BEGIN
            CLOSE cur;
            DEALLOCATE cur;
        END
        
        -- Generar un mensaje de error personalizado si falla todo el bloque
        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR('Error en el procedimiento almacenado: %s', 16, 1, @ErrorMessage);
    END CATCH
END;
