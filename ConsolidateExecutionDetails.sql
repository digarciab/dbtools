USE [dbtools]
GO
/************************************************************************************************* 
 * StoredProcedure: [dbo].[ConsolidateExecutionDetails]
 * Creado por: Daniel Israel
 * Fecha de creación: 01 de abril de 2024
 * Descripción: Procedimiento almacenado para consolidar los scripts ejecutados
 * GitHub: https://github.com/digarciab/dbtools
 *************************************************************************************************/
ALTER PROCEDURE [dbo].[ConsolidateExecutionDetails]
AS
BEGIN
    DECLARE @yesterday DATE = CONVERT(DATE, DATEADD(DAY, -1, GETDATE()));

    INSERT INTO [dbtools].[dbo].[ExecutionSummaryLog] (
        [fecha],
        [objectname],
        [application],
        [databaseid],
        [databasename],
        [avg_duration],
        [avg_reads],
        [avg_writes],
        [avg_cpu],
        [rowcounts],
        [exec_count]
    )
    SELECT
        @yesterday,
        [objectname],
        max([application]),
        max([databaseid]),
        max([databasename]),
        AVG([avg_duration]) AS [avg_duration],
        AVG([reads]) AS [avg_reads],
        AVG([writes]) AS [avg_writes],
        AVG([cpu]) AS [avg_cpu],
        SUM([rowcounts]) AS [rowcounts],
        SUM([exec_count]) AS [exec_count]
    FROM
        [dbtools].[dbo].[ExecutionDetailsLog]
    WHERE
        [fecha] = @yesterday and isnull(objectname,'')<>''
    GROUP BY
        [objectname]
END;
