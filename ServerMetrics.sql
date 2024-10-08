USE [dbtools]
GO
/************************************************************************************************* 
 * StoredProcedure: [dbo].[ServerMetrics]
 * Creado por: Daniel Israel
 * Fecha de creación: 01 de abril de 2024
 * Descripción: Procedimiento almacenado para mostrar las estadisticas de servidor
 * GitHub: https://github.com/digarciab/dbtools
 *************************************************************************************************/
ALTER     PROCEDURE [dbo].[ServerMetrics]
    @QueryId INT
AS
BEGIN
    /*
        QueryId Labels:
        1 - DBSize: 
        2 - DBExpensive: 
        3 - DBGrow: 
        4 - TabExpensive: 
        5 - TabGrow:
        6 - IndExpensive: 
        7 - IndGrow:
        8 - IndFrag: 
        9 - FragGrow: 
        10 - IndUnused: 
		11 - UnusedHist:
		12 - IndScans:
		13 - 
		14 - 
    */

    SET NOCOUNT ON;

	IF @QueryId = 1
	BEGIN
		-- 1. DBSize: Histórico de Crecimiento y Tamaño de disco usado por todas las BDs(%,MB)
		WITH DailyDatabaseSize AS (
			SELECT CONVERT(date, RecordDateTime) AS RecordDate, CAST(SUM(DatabaseSize) AS bigint) AS TotalDatabaseSizeMB,
			CAST(SUM(Reserved+UnallocatedSpace) AS bigint) AS TotalDataMB,
			CAST(SUM(LogUsed+LogUnused) AS bigint) AS TotalLogMB
			FROM DatabaseSpaceUsage
			GROUP BY CONVERT(date, RecordDateTime)
		)
		SELECT Top 10
			RecordDate, 
			TotalDataMB,
			TotalLogMB,
			TotalDatabaseSizeMB, 
			LAG(TotalDatabaseSizeMB) OVER (ORDER BY RecordDate) AS PreviousTotalDatabaseSizeMB,
			TotalDatabaseSizeMB - LAG(TotalDatabaseSizeMB) OVER (ORDER BY RecordDate) AS GrowthMB,
			CAST(ROUND(((TotalDatabaseSizeMB - LAG(TotalDatabaseSizeMB) OVER (ORDER BY RecordDate))* 100.00 / 
			LAG(TotalDatabaseSizeMB) OVER (ORDER BY RecordDate)),2) AS DECIMAL(10,2)) AS GrowthPercentage
		FROM DailyDatabaseSize
		ORDER BY RecordDate DESC;
	END

	ELSE IF @QueryId = 2
	BEGIN
		-- 2. DBExpensive: Lista de BD con espacio reservado mas grandes
		WITH CurrentDayData AS (
			SELECT 
				DatabaseName,
				cast(round(Reserved+UnallocatedSpace, 0) as bigint) AS DataMB,
				cast(round(LogUsed+LogUnused, 0) as bigint) AS LogMB,
				cast(round(DatabaseSize, 0) as bigint) AS DatabaseSizeMB
			FROM DatabaseSpaceUsage
			WHERE CONVERT(date, RecordDateTime) = CONVERT(date, GETDATE())
		),
		PreviousDayData AS (
			SELECT 
				DatabaseName,
				cast(round(DatabaseSize, 0) as bigint) AS DatabaseSizeMB
			FROM DatabaseSpaceUsage
			WHERE CONVERT(date, RecordDateTime) = CONVERT(date, DATEADD(day, -1, GETDATE()))
		)
		SELECT Top 10 
			c.DatabaseName,
			c.DataMB,
			c.LogMB,
			c.DatabaseSizeMB,
			p.DatabaseSizeMB AS PreviousReservedSpaceMB,
			ISNULL(c.DatabaseSizeMB - p.DatabaseSizeMB, 0) AS GrowthMB,
			CAST(CASE 
				WHEN p.DatabaseSizeMB > 0 
				THEN ROUND(((c.DatabaseSizeMB - p.DatabaseSizeMB) * 100.0) / p.DatabaseSizeMB, 2) 
				ELSE 0 
			END AS DECIMAL (10,2)) AS GrowthPercent
		FROM CurrentDayData c
		LEFT JOIN PreviousDayData p ON c.DatabaseName = p.DatabaseName
		ORDER BY c.DatabaseSizeMB DESC;
	END

	ELSE IF @QueryId = 3
	BEGIN
		-- 3. DBGrow: Histórico de Crecimiento y Tamaño de Database
		WITH Top10Databases AS (
			SELECT TOP 10
				DatabaseName,
				SUM(DatabaseSize) AS TotalSize
			FROM DatabaseSpaceUsage
			WHERE CONVERT(date, RecordDateTime) = CONVERT(date, GETDATE())
			GROUP BY DatabaseName
			ORDER BY TotalSize DESC
		),
		HistoricalData AS (
			SELECT
				ds.DatabaseName,
				ds.RecordDateTime,
				CAST(ROUND(ds.Reserved + ds.UnallocatedSpace, 0) AS bigint) AS DataMB,
				CAST(ROUND(ds.LogUsed + ds.LogUnused, 0) AS bigint) AS LogMB,
				CAST(ROUND(ds.Reserved, 0) AS bigint) AS DataUsedMB,
				t.TotalSize,
				LAG(CAST(ROUND(ds.Reserved, 0) AS bigint), 1, NULL)
					OVER (PARTITION BY ds.DatabaseName ORDER BY ds.RecordDateTime) AS PreviousDataUsedMB
			FROM
				DatabaseSpaceUsage ds
				inner join Top10Databases t on t.databasename = ds.DatabaseName
			WHERE ds.RecordDateTime >= DATEADD(day, -10, GETDATE())
		)
		SELECT
			hd.DatabaseName,
			hd.RecordDateTime,
			hd.DataMB,
			hd.LogMB,
			hd.DataUsedMB,
			ISNULL(hd.PreviousDataUsedMB, 0) AS PreviousDataUsedMB,
			CASE 
				WHEN ISNULL(hd.PreviousDataUsedMB, 0) = 0 THEN 0
				ELSE CAST(
					(
						ROUND(hd.DataUsedMB - ISNULL(hd.PreviousDataUsedMB, 0),0) 
					) 
					AS bigint
				)
			END AS GrowthMB,
			CASE 
				WHEN ISNULL(hd.PreviousDataUsedMB, 0) = 0 THEN 0
				ELSE CAST(
					(
						(hd.DataUsedMB - ISNULL(hd.PreviousDataUsedMB, 0)) * 100.0 / 
						ISNULL(NULLIF(hd.PreviousDataUsedMB, 0), 1.0)
					) 
					AS decimal(10, 2)
				)
			END AS GrowthPercentage
		FROM
			HistoricalData hd
		ORDER BY
			hd.TotalSize desc,
			hd.DatabaseName,
			hd.RecordDateTime DESC;
	END

	ELSE IF @QueryId = 4
	BEGIN
		-- 4. TabExpensive: Lista de Tablas con espacio reservado mas grandes
		SELECT Top 10 DatabaseName, SchemaName, TableName,DatabaseName+'.'+SchemaName+'.'+TableName as Tabla, cast(round(Reserved,0) as bigint) AS ReservedSpaceMB
		FROM DatabaseTableSpaceUsage
		WHERE CONVERT(date, RecordDateTime) = CONVERT(date, GETDATE())
		ORDER BY ReservedSpaceMB DESC;
	END

	ELSE IF @QueryId = 5
	BEGIN
		-- 5. TabGrow: Histórico de Crecimiento y Tamaño de Tabla
		WITH Top10Tables AS (
				SELECT TOP 10 DatabaseName,SchemaName,TableName,Reserved
				FROM DatabaseTableSpaceUsage
				WHERE CONVERT(date, RecordDateTime) = CONVERT(date, GETDATE())
				ORDER BY Reserved DESC 
		)
		SELECT 
			a.DatabaseName, 
			a.SchemaName, 
			a.TableName, 
			RecordDateTime, 
			CAST(ROUND(a.Reserved, 0) AS bigint) AS TableSizeMB, 
			CAST(ROUND(ISNULL(LAG(a.Reserved) OVER (PARTITION BY a.DatabaseName, a.SchemaName, a.TableName ORDER BY RecordDateTime), 0), 0) AS bigint) AS PreviousTableSize,
			CASE 
				WHEN ISNULL(LAG(a.Reserved) OVER (PARTITION BY a.DatabaseName, a.SchemaName, a.TableName ORDER BY RecordDateTime), 0) = 0 THEN 0
				ELSE CAST(ROUND(a.Reserved - ISNULL(LAG(a.Reserved) OVER (PARTITION BY a.DatabaseName, a.SchemaName, a.TableName ORDER BY RecordDateTime), 0), 0) AS bigint)
			END AS GrowthMB,
			CASE 
				WHEN ISNULL(LAG(a.Reserved) OVER (PARTITION BY a.DatabaseName, a.SchemaName, a.TableName ORDER BY RecordDateTime), 0) = 0 THEN 0
				ELSE CAST(
					(
						(a.Reserved - ISNULL(LAG(a.Reserved) OVER (PARTITION BY a.DatabaseName, a.SchemaName, a.TableName ORDER BY RecordDateTime), 0)) / 
						ISNULL(NULLIF(LAG(a.Reserved) OVER (PARTITION BY a.DatabaseName, a.SchemaName, a.TableName ORDER BY RecordDateTime), 0), 1.0)
					) * 100 
					AS decimal(10, 2)
				)
			END AS GrowthPercentage
		FROM DatabaseTableSpaceUsage a
		inner join Top10Tables b on a.DatabaseName = b.DatabaseName and a.SchemaName=b.SchemaName and a.TableName=b.TableName
		WHERE 
			RecordDateTime > CAST(DATEADD(DAY, -9, GETDATE()) AS DATE)
		ORDER BY 
			b.Reserved DESC,
			a.DatabaseName, 
			a.SchemaName, 
			a.TableName, 
			RecordDateTime DESC;
	END

	ELSE IF @QueryId = 6
	BEGIN
		-- 6. IndExpensive: Lista de Índices con espacio reservado mas grandes
		SELECT Top 10 DatabaseName, TableName, IndexName,DatabaseName+'.'+TableName+'.'+IndexName as Indice, cast(round(SizeMB,0)as bigint) AS IndexSizeMB
		FROM IndexFragmentationHistory
		WHERE RecordDate = CONVERT(date, GETDATE())
		ORDER BY IndexSizeMB DESC;
	END

	ELSE IF @QueryId = 7
	BEGIN
		-- 7. IndGrow: Histórico de Crecimiento y Tamaño de Índice
		WITH Top10LargestIndexes AS (
			SELECT TOP 10 
				DatabaseName, 
				TableName, 
				IndexName,
				SizeMB
			FROM IndexFragmentationHistory
			WHERE CONVERT(date, RecordDate) = CONVERT(date, GETDATE())
			ORDER BY SizeMB DESC
		), DateRange AS (
			SELECT CAST(DATEADD(DAY, v.number - 9, GETDATE()) AS DATE) AS RecordDate
			FROM master..spt_values v
			WHERE v.type = 'P' AND v.number BETWEEN 0 AND 9
		)
		SELECT 
			dr.RecordDate, 
			t.DatabaseName, 
			t.TableName, 
			t.IndexName, 
			CAST(ROUND(h.SizeMB, 0) AS bigint) AS IndexSizeMB, 
			CAST(ROUND(ISNULL(LAG(h.SizeMB) OVER (PARTITION BY t.DatabaseName, t.TableName, t.IndexName ORDER BY dr.RecordDate), 0), 0) AS bigint) AS PreviousIndexSize,
			CASE 
				WHEN ISNULL(LAG(h.SizeMB) OVER (PARTITION BY t.DatabaseName, t.TableName, t.IndexName ORDER BY dr.RecordDate), 0) = 0 THEN 0
				ELSE CAST(ROUND(h.SizeMB - ISNULL(LAG(h.SizeMB) OVER (PARTITION BY t.DatabaseName, t.TableName, t.IndexName ORDER BY dr.RecordDate), 0), 0) AS bigint)
			END AS GrowthMB,
			CASE 
				WHEN ISNULL(LAG(h.SizeMB) OVER (PARTITION BY t.DatabaseName, t.TableName, t.IndexName ORDER BY dr.RecordDate), 0) = 0 THEN 0
				ELSE CAST(
					(
						(h.SizeMB - ISNULL(LAG(h.SizeMB) OVER (PARTITION BY t.DatabaseName, t.TableName, t.IndexName ORDER BY dr.RecordDate), 0)) / 
						ISNULL(NULLIF(LAG(h.SizeMB) OVER (PARTITION BY t.DatabaseName, t.TableName, t.IndexName ORDER BY dr.RecordDate), 0), 1.0)
					) * 100 
					AS decimal(10, 2)
				)
			END AS GrowthPercentage
		FROM DateRange dr
		CROSS JOIN Top10LargestIndexes t
		LEFT JOIN IndexFragmentationHistory h 
			ON dr.RecordDate = CONVERT(date, h.RecordDate) 
			AND t.DatabaseName = h.DatabaseName 
			AND t.TableName = h.TableName 
			AND t.IndexName = h.IndexName
		ORDER BY t.SizeMB DESC, t.DatabaseName, t.TableName, t.IndexName, dr.RecordDate DESC;
	END

	ELSE IF @QueryId = 8
	BEGIN
		-- 8. IndFrag: Lista de Índices pesados con alta fragmentación
		SELECT Top 10 DatabaseName, TableName, IndexName,DatabaseName+'.'+TableName+'.'+IndexName as Indice,  FragmentationPercent, cast(round(SizeMB,0)as bigint) AS IndexSizeMB 
		FROM IndexFragmentationHistory
		WHERE RecordDate = CONVERT(date, GETDATE()) and FragmentationPercent>30 and SizeMB>10
		ORDER BY IndexSizeMB DESC;
	END

	ELSE IF @QueryId = 9
	BEGIN
		-- 9. FragGrow: Histórico de Fragmentación de Índice
		WITH Top10LargestIndexes AS (
			SELECT TOP 10 
				DatabaseName, 
				TableName, 
				IndexName,
				SizeMB
			FROM IndexFragmentationHistory
			WHERE CONVERT(date, RecordDate) = CONVERT(date, GETDATE()) and FragmentationPercent>30 and SizeMB>10
			ORDER BY SizeMB DESC
		), DateRange AS (
			SELECT CAST(DATEADD(DAY, v.number - 9, GETDATE()) AS DATE) AS RecordDate
			FROM master..spt_values v
			WHERE v.type = 'P' AND v.number BETWEEN 0 AND 9
		)
		SELECT 
			dr.RecordDate, 
			t.DatabaseName, 
			t.TableName, 
			t.IndexName, 
			h.FragmentationPercent, 
			cast(round(h.SizeMB,0)as bigint) AS IndexSizeMB 
		FROM DateRange dr
		CROSS JOIN Top10LargestIndexes t
		LEFT JOIN IndexFragmentationHistory h 
			ON dr.RecordDate = CONVERT(date, h.RecordDate) 
			AND t.DatabaseName = h.DatabaseName 
			AND t.TableName = h.TableName 
			AND t.IndexName = h.IndexName
		ORDER BY t.SizeMB DESC, t.DatabaseName, t.TableName, t.IndexName, dr.RecordDate DESC;
	END

	ELSE IF @QueryId = 10
	BEGIN
		-- 10. IndUnused: Lista de Índices no utilizados
		SELECT Top 10 DatabaseName, TableName, IndexName, cast(round(SizeMB,0)as bigint) SizeMB
		FROM IndexFragmentationHistory
		WHERE RecordDate = CONVERT(date, GETDATE()) AND
			  UserSeeks = 0 AND UserScans = 0 AND UserLookups = 0
		ORDER BY SizeMB DESC;
	END

	ELSE IF @QueryId = 11
	BEGIN
		-- 11. UnusedHist: Histórico de utilización de Índice
		WITH Top10LargestIndexes AS (
			SELECT TOP 10 
				DatabaseName, 
				TableName, 
				IndexName,
				SizeMB
			FROM IndexFragmentationHistory
			WHERE CONVERT(date, RecordDate) = CONVERT(date, GETDATE()) AND
			  UserSeeks = 0 AND UserScans = 0 AND UserLookups = 0
			ORDER BY SizeMB DESC
		), DateRange AS (
			SELECT CAST(DATEADD(DAY, v.number - 9, GETDATE()) AS DATE) AS RecordDate
			FROM master..spt_values v
			WHERE v.type = 'P' AND v.number BETWEEN 0 AND 9
		)
		SELECT 
			dr.RecordDate, 
			t.DatabaseName, 
			t.TableName, 
			t.IndexName, 
			h.UserSeeks, 
			h.UserScans, 
			h.UserLookups, 
			h.UserUpdates,
			cast(round(h.SizeMB,0)as bigint) SizeMB
		FROM DateRange dr
		CROSS JOIN Top10LargestIndexes t
		LEFT JOIN IndexFragmentationHistory h 
			ON dr.RecordDate = CONVERT(date, h.RecordDate) 
			AND t.DatabaseName = h.DatabaseName 
			AND t.TableName = h.TableName 
			AND t.IndexName = h.IndexName
		ORDER BY t.SizeMB DESC, t.DatabaseName, t.TableName, t.IndexName, dr.RecordDate DESC;
	END

	ELSE IF @QueryId = 12
    BEGIN
		-- 12. IndScans: Lista de Índices con escaneos
		SELECT Top 10 DatabaseName, TableName, IndexName, UserScans,cast(round(SizeMB,0)as bigint) SizeMB
		FROM IndexFragmentationHistory
		WHERE RecordDate = CONVERT(date, GETDATE())
		and UserScans> 499999
		ORDER BY SizeMB DESC;
    END
	
	ELSE IF @QueryId = 13
	BEGIN
		-- 13. Lista de BD con archivo de datos mas grandes
		SELECT Top 10 DatabaseName, cast(round(Reserved+UnallocatedSpace,0) as bigint) AS DataMB, cast(round(Reserved,0) as bigint) AS DataUsedMB, 
		cast(round(UnallocatedSpace,0) as bigint) AS DataUnUsedMB, RecordDateTime
		FROM DatabaseSpaceUsage
		WHERE CONVERT(date, RecordDateTime) = CONVERT(date, GETDATE())
		ORDER BY UnallocatedSpace DESC;
	END

	ELSE IF @QueryId = 14
	BEGIN
		-- 14. Lista de BD con archivo de log mas grandes
		SELECT Top 10 DatabaseName, cast(round(LogUsed+LogUnused,0) as bigint) AS LogMB, cast(round(LogUsed,0) as bigint) AS LogUsedMB, 
		cast(round(LogUnused,0) as bigint) AS LogUnUsedMB, RecordDateTime
		FROM DatabaseSpaceUsage
		WHERE CONVERT(date, RecordDateTime) = CONVERT(date, GETDATE())
		ORDER BY LogUnused DESC;
	END
	
END