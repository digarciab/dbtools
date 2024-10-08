USE [dbtools]
GO
/************************************************************************************************* 
 * StoredProcedure: [dbo].[DatabaseMetrics]
 * Creado por: Daniel Israel
 * Fecha de creación: 01 de abril de 2024
 * Descripción: Procedimiento almacenado para mostrar las estadisticas de metricas recolectadas por BD
 * GitHub: https://github.com/digarciab/dbtools
 *************************************************************************************************/
ALTER   PROCEDURE [dbo].[DatabaseMetrics]
    @DatabaseName NVARCHAR(255),
    @QueryId INT
--WITH EXECUTE AS 'dbo'
AS
BEGIN
    /*
        QueryId Labels:
        1 - DBGrow: Histórico de Crecimiento y Tamaño de Database
        2 - TabExpensive: Lista de Tablas con espacio reservado más grandes
        3 - TabGrow: Histórico de Crecimiento y Tamaño de Tabla
        4 - IndExpensive: Lista de Índices con espacio reservado más grandes
        5 - IndGrow: Histórico de Crecimiento y Tamaño de Índice
        6 - IndFrag: Lista de Índices pesados con alta fragmentación
        7 - FragGrow: Histórico de Fragmentación de Índice
        8 - IndUnused: Lista de Índices no utilizados
        9 - IndUnusedHist: Histórico de Índices no utilizados
        10 - IndScans: Lista de Índices más escaneados
		11 - FKNonexistent: Lista relaciones y claves foraneas inexistentes
		12 - TopAvgDuration: Top 10 Sentencias con mayor promedio de duración
		13 - TopAvgDurationHist: Historico de Serntencias Top 10 con mayor promedio de duración
		14 - IdxFaltantes: List de Indices Faltantes
    */

    SET NOCOUNT ON;

	IF @QueryId = 1
	BEGIN
		-- 1. DBGrow: Histórico de Crecimiento y Tamaño de Database
		WITH HistoricalData AS (
			SELECT
				ds.DatabaseName,
				ds.RecordDateTime,
				CAST(ROUND(ds.Reserved + ds.UnallocatedSpace, 0) AS bigint) AS DataMB,
				CAST(ROUND(ds.LogUsed + ds.LogUnused, 0) AS bigint) AS LogMB,
				CAST(ROUND(ds.Reserved, 0) AS bigint) AS DataUsedMB,
				LAG(CAST(ROUND(ds.Reserved, 0) AS bigint), 1, NULL)
				OVER (PARTITION BY ds.DatabaseName ORDER BY ds.RecordDateTime) AS PreviousDataUsedMB
			FROM
				DatabaseSpaceUsage ds
			WHERE
				ds.DatabaseName = @DatabaseName
				AND ds.RecordDateTime >= DATEADD(day, -10, GETDATE())
		), DateRange AS (
			SELECT CAST(DATEADD(DAY, v.number - 9, GETDATE()) AS DATE) AS RecordDate
			FROM master..spt_values v
			WHERE v.type = 'P' AND v.number BETWEEN 0 AND 9
		)
		SELECT 
			@DatabaseName 'DBGrow',
			dr.RecordDate,
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
			END AS GrowthPercentage,
			hd.DataMB,
			hd.LogMB
		FROM DateRange dr
		LEFT JOIN HistoricalData hd ON dr.RecordDate = CONVERT(date, hd.RecordDateTime) 
		ORDER BY dr.RecordDate desc;
	END

	ELSE IF @QueryId = 2
	BEGIN
		-- 2. TabExpensive: Lista de Tablas con espacio reservado más grandes
		SELECT Top 10 
			DatabaseName 'TabExpensive', 
			SchemaName, 
			TableName,
			CAST(ROUND(Reserved, 0) AS bigint) AS ReservedSpaceMB,
			NumRows
		FROM 
			DatabaseTableSpaceUsage
		WHERE 
			CONVERT(date, RecordDateTime) = CONVERT(date, GETDATE()) 
			AND Reserved > 10
			AND DatabaseName = @DatabaseName
		ORDER BY 
			ReservedSpaceMB DESC;
	END

	ELSE IF @QueryId = 3
	BEGIN
		-- 3. TabGrow: Histórico de Crecimiento y Tamaño de Tabla
		WITH Top10Tables AS	(
				SELECT TOP 10 DatabaseName, SchemaName, TableName, Reserved
				FROM DatabaseTableSpaceUsage
				WHERE CONVERT(date, RecordDateTime) = CONVERT(date, GETDATE()) 
				AND Reserved > 10
				AND DatabaseName = @DatabaseName
				ORDER BY Reserved DESC
			)
		SELECT 
			a.DatabaseName 'TabGrow', 
			a.SchemaName, 
			a.TableName, 
			CAST(RecordDateTime AS date) AS RecordDate, 
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
			END AS GrowthPercentage,
			a.NumRows
		FROM DatabaseTableSpaceUsage a
		INNER JOIN Top10Tables b on a.DatabaseName = b.DatabaseName and a.SchemaName=b.SchemaName and a.TableName=b.TableName
		WHERE RecordDateTime > CAST(DATEADD(DAY, -9, GETDATE()) AS DATE) AND A.Reserved > 10
		ORDER BY 
			b.Reserved DESC,
			a.SchemaName, 
			a.TableName, 
			a.RecordDateTime DESC;
	END

	ELSE IF @QueryId = 4
	BEGIN
		-- 4. IndExpensive: Lista de Índices con espacio reservado más grandes
		SELECT Top 10 
			DatabaseName 'IndExpensive', 
			TableName, 
			IndexName, 
			CAST(ROUND(SizeMB,0) AS bigint) AS IndexSizeMB
		FROM 
			IndexFragmentationHistory
		WHERE 
			RecordDate = CONVERT(date, GETDATE()) 
			AND SizeMB > 10
			AND DatabaseName = @DatabaseName
		ORDER BY 
			IndexSizeMB DESC;
	END

	ELSE IF @QueryId = 5
	BEGIN
		-- 5. IndGrow: Histórico de Crecimiento y Tamaño de Índice
		WITH Top10LargestIndexes AS (
			SELECT TOP 10 
				DatabaseName, 
				TableName, 
				IndexName,
				SizeMB
			FROM IndexFragmentationHistory
			WHERE CONVERT(date, RecordDate) = CONVERT(date, GETDATE()) 
			AND SizeMB > 10
			AND DatabaseName = @DatabaseName
			ORDER BY SizeMB DESC
		), DateRange AS (
			SELECT CAST(DATEADD(DAY, v.number - 9, GETDATE()) AS DATE) AS RecordDate
			FROM master..spt_values v
			WHERE v.type = 'P' AND v.number BETWEEN 0 AND 9
		)
		SELECT 
			t.DatabaseName 'IndGrow', 
			t.TableName, 
			t.IndexName, 
			dr.RecordDate,
			CAST(ROUND(ISNULL(h.SizeMB,0), 0) AS bigint) AS IndexSizeMB, 
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
		ORDER BY t.SizeMB DESC,t.DatabaseName, t.TableName, t.IndexName, dr.RecordDate DESC;
	END

	ELSE IF @QueryId = 6
	BEGIN
		-- 6. IndFrag: Lista de Índices pesados con alta fragmentación
		SELECT Top 10 
			DatabaseName 'IndFrag', 
			TableName, 
			IndexName, 
			FragmentationPercent, 
			CAST(ROUND(SizeMB,0) AS bigint) AS IndexSizeMB 
		FROM 
			IndexFragmentationHistory
		WHERE 
			RecordDate = CONVERT(date, GETDATE()) 
			AND FragmentationPercent > 30 
			AND SizeMB > 10  
			AND DatabaseName = @DatabaseName
		ORDER BY 
			IndexSizeMB DESC;
	END

	ELSE IF @QueryId = 7
	BEGIN
		-- 7. FragGrow: Histórico de Fragmentación de Índice
		WITH Top10LargestIndexes AS (
			SELECT TOP 10 
				DatabaseName, 
				TableName, 
				IndexName,
				SizeMB
			FROM IndexFragmentationHistory
			WHERE CONVERT(date, RecordDate) = CONVERT(date, GETDATE())  and FragmentationPercent>30 and SizeMB>10 
			AND DatabaseName = @DatabaseName
			ORDER BY SizeMB DESC
		), DateRange AS (
			SELECT CAST(DATEADD(DAY, v.number - 9, GETDATE()) AS DATE) AS RecordDate
			FROM master..spt_values v
			WHERE v.type = 'P' AND v.number BETWEEN 0 AND 9
		)
		SELECT 
			t.DatabaseName 'FragGrow', 
			t.TableName, 
			t.IndexName, 
			dr.RecordDate, 
			isnull(h.FragmentationPercent,0) 'FragmentationPercent',
			isnull(LAG(h.FragmentationPercent) OVER (PARTITION BY t.DatabaseName, t.TableName, t.IndexName ORDER BY dr.RecordDate),0) AS PreviousFragmentationPercent,
			CASE 
				WHEN LAG(h.FragmentationPercent) OVER (PARTITION BY t.DatabaseName, t.TableName, t.IndexName ORDER BY dr.RecordDate) IS NULL THEN 0
				ELSE h.FragmentationPercent - LAG(h.FragmentationPercent) OVER (PARTITION BY t.DatabaseName, t.TableName, t.IndexName ORDER BY dr.RecordDate)
			END AS FragmentationChange,
			isnull(cast(round(h.SizeMB,0)as bigint),0) AS IndexSizeMB 
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
		-- 8. IndUnused: Lista de Índices no utilizados
		SELECT Top 10 
			DatabaseName 'IndUnused', 
			TableName, 
			IndexName, 
			CAST(ROUND(SizeMB, 0) AS bigint) AS IndexSizeMB
		FROM 
			IndexFragmentationHistory
		WHERE 
			CONVERT(date, RecordDate) = CONVERT(date, GETDATE()) AND SizeMB > 10  
			AND UserSeeks = 0 
			AND UserScans = 0 
			AND UserLookups = 0        
			AND DatabaseName = @DatabaseName
		ORDER BY 
			IndexSizeMB DESC;
	END

	ELSE IF @QueryId = 9
	BEGIN
		-- 9. IndUnusedHist: Histórico de Índices no utilizados
		WITH Top10LargestIndexes AS (
			SELECT TOP 10 
				DatabaseName, 
				TableName, 
				IndexName,
				SizeMB
			FROM IndexFragmentationHistory
			WHERE CONVERT(date, RecordDate) = CONVERT(date, GETDATE()) AND SizeMB > 10
				AND DatabaseName = @DatabaseName 
				AND UserSeeks = 0 AND UserScans = 0 AND UserLookups = 0
			ORDER BY SizeMB DESC
		), DateRange AS (
			SELECT CAST(DATEADD(DAY, v.number - 9, GETDATE()) AS DATE) AS RecordDate
			FROM master..spt_values v
			WHERE v.type = 'P' AND v.number BETWEEN 0 AND 9
		)
		SELECT 
			t.DatabaseName 'IndUnusedHist', 
			t.TableName, 
			t.IndexName, 
			dr.RecordDate, 
			isnull(h.UserSeeks,0) UserSeeks, 
			isnull(h.UserScans,0) UserScans, 
			isnull(h.UserLookups,0) UserLookups, 
			isnull(h.UserUpdates,0) UserUpdates,
			isnull(cast(round(h.SizeMB,0)as bigint),0) SizeMB
		FROM DateRange dr
		CROSS JOIN Top10LargestIndexes t
		LEFT JOIN IndexFragmentationHistory h 
			ON dr.RecordDate = CONVERT(date, h.RecordDate) 
			AND t.DatabaseName = h.DatabaseName 
			AND t.TableName = h.TableName 
			AND t.IndexName = h.IndexName
		ORDER BY t.SizeMB DESC,t.DatabaseName, t.TableName, t.IndexName,dr.RecordDate DESC;
	END

	ELSE IF @QueryId = 10
	BEGIN
		-- 10. IndScans: Histórico de Índices más escaneados
		SELECT Top 10 DatabaseName 'IndScans', TableName, IndexName, UserScans,cast(round(SizeMB,0)as bigint) SizeMB
		FROM IndexFragmentationHistory
		WHERE RecordDate = CONVERT(date, GETDATE()) AND DatabaseName = @DatabaseName AND
		UserScans> 499999 and SizeMB>10
		ORDER BY SizeMB DESC;	
	END

	ELSE IF @QueryId = 11
	BEGIN
		-- 11. FKNonexistent: Lista relaciones y claves foraneas inexistentes
		DECLARE @sql NVARCHAR(MAX);

		-- Tabla temporal para almacenar resultados
		IF OBJECT_ID('tempdb..#ParentChildCandidates') IS NOT NULL DROP TABLE #ParentChildCandidates;
		CREATE TABLE #ParentChildCandidates (
			DatabaseName NVARCHAR(128),
			ParentSchema NVARCHAR(128),
			ParentTable NVARCHAR(128),
			ChildSchema NVARCHAR(128),
			ChildTable NVARCHAR(128),
			CommonColumns NVARCHAR(MAX)  -- Usamos NVARCHAR(MAX) para almacenar una lista de columnas
		);

		-- Construcción dinámica del SQL para la base de datos especificada
		SET @sql = N'
		USE ' + QUOTENAME(@DatabaseName) + ';
		WITH ParentTables AS (
			SELECT 
				s.name AS ParentSchema,
				t.name AS ParentTable,
				STUFF((SELECT '','' + c.name
					   FROM sys.columns c
					   WHERE c.object_id = t.object_id
					   AND c.column_id IN (SELECT column_id 
										   FROM sys.index_columns ic 
										   WHERE ic.object_id = t.object_id 
										   AND ic.index_id = i.index_id)
					   ORDER BY c.column_id
					   FOR XML PATH('''')), 1, 1, '''') AS CommonColumns
			FROM 
				sys.tables t
				JOIN sys.schemas s ON t.schema_id = s.schema_id
				JOIN sys.index_columns ic ON t.object_id = ic.object_id
				JOIN sys.indexes i ON ic.object_id = i.object_id AND ic.index_id = i.index_id
			WHERE 
				i.is_primary_key = 1
			GROUP BY
				s.name,
				t.name,
				t.object_id,
				i.index_id
		),
		ChildTables AS (
			SELECT 
				s.name AS ChildSchema,
				t.name AS ChildTable,
				c.name AS CommonColumn,
				ty.name AS DataType
			FROM 
				sys.tables t
				JOIN sys.schemas s ON t.schema_id = s.schema_id
				JOIN sys.columns c ON t.object_id = c.object_id
				JOIN sys.types ty ON c.user_type_id = ty.user_type_id
		)
		, CommonColumnsCheck AS (
			SELECT 
				p.ParentSchema,
				p.ParentTable,
				c.ChildSchema,
				c.ChildTable,
				p.CommonColumns,
				COUNT(DISTINCT c.CommonColumn) AS CommonColumnCount
			FROM 
				ParentTables p
				JOIN ChildTables c ON '','' + p.CommonColumns + '','' LIKE ''%,'' + c.CommonColumn + '',%''
			GROUP BY 
				p.ParentSchema,
				p.ParentTable,
				c.ChildSchema,
				c.ChildTable,
				p.CommonColumns
			HAVING COUNT(DISTINCT c.CommonColumn) = LEN(p.CommonColumns) - LEN(REPLACE(p.CommonColumns, '','', '''')) + 1
		)
		INSERT INTO #ParentChildCandidates (DatabaseName, ParentSchema, ParentTable, ChildSchema, ChildTable, CommonColumns)
		SELECT DISTINCT
			''' + @DatabaseName + ''' AS DatabaseName,
			c.ParentSchema,
			c.ParentTable,
			c.ChildSchema,
			c.ChildTable,
			c.CommonColumns
		FROM 
			CommonColumnsCheck c
			LEFT JOIN sys.foreign_key_columns fkc ON fkc.parent_object_id = OBJECT_ID(c.ParentSchema + ''.'' + c.ParentTable)
				AND fkc.referenced_object_id = OBJECT_ID(c.ChildSchema + ''.'' + c.ChildTable)
		WHERE 
			fkc.constraint_object_id IS NULL
			AND c.ParentSchema <> c.ChildSchema 
			AND c.ParentTable <> c.ChildTable;
		';
		EXEC sp_executesql @sql;

		-- Seleccionamos las 10 tablas hijas más grandes
		WITH LargestChildTables AS (
			SELECT 
				pcc.ChildSchema,
				pcc.ChildTable,
				ifh.Reserved
			FROM 
				#ParentChildCandidates pcc
				JOIN DatabaseTableSpaceUsage ifh ON ifh.DatabaseName = pcc.DatabaseName 
					AND ifh.TableName = pcc.ChildTable
					AND CONVERT(date, ifh.RecordDateTime) = CONVERT(date, GETDATE())
					AND ifh.Reserved > 10
		)
		, RankedChildTables AS (
			SELECT 
				lct.ChildSchema,
				lct.ChildTable,
				lct.Reserved,
				ROW_NUMBER() OVER (PARTITION BY lct.ChildSchema, lct.ChildTable ORDER BY lct.Reserved DESC) AS rn
			FROM 
				LargestChildTables lct
			WHERE
				lct.Reserved > 10
		)
		, Top10ChildTables AS (
			SELECT 
				ChildSchema,
				ChildTable
			FROM 
				RankedChildTables
			WHERE 
				rn = 1
			ORDER BY 
				Reserved DESC
			OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY
		)

		-- Obtenemos todos los registros de las 10 tablas hijas más grandes
		SELECT 
			pcc.DatabaseName 'FKNonexistent',
			pcc.ParentSchema + '.' + pcc.ParentTable AS ParentTable,
			pcc.ChildSchema + '.' + pcc.ChildTable AS ChildTable,
			pcc.CommonColumns,
			ifh.Reserved
		FROM 
			#ParentChildCandidates pcc
			JOIN DatabaseTableSpaceUsage ifh ON ifh.DatabaseName = pcc.DatabaseName 
				AND ifh.TableName = pcc.ChildTable
				AND CONVERT(date, ifh.RecordDateTime) = CONVERT(date, GETDATE())
				AND ifh.Reserved > 10
			JOIN Top10ChildTables t10 ON t10.ChildSchema = pcc.ChildSchema
				AND t10.ChildTable = pcc.ChildTable
		ORDER BY ifh.Reserved DESC,
			ChildTable,
			pcc.CommonColumns,
			ParentTable;

		-- Limpiamos las tablas temporales
		DROP TABLE #ParentChildCandidates;

	END

	ELSE IF @QueryId = 12

    BEGIN
        -- 12. TopAvgDuration: Top 10 Sentencias con mayor promedio de duración
		WITH DurationSummary AS (
			SELECT TOP 10 
				[objectname],
				AVG([avg_duration]) AS TotalAvgDuration
			FROM ExecutionSummaryLog
			WHERE [fecha] >= CONVERT(DATE, DATEADD(DAY, -10, GETDATE())) 
			  AND [databasename] = @DatabaseName
			GROUP BY [objectname]
			ORDER BY AVG([avg_duration])  DESC
		),
		LatestValues AS (
			SELECT
				[objectname],
				[avg_duration],
				[Avg_Reads],
				[Avg_Writes],
				[Avg_CPU],
				[RowCounts],
				[Exec_Count]
			FROM ExecutionSummaryLog
			WHERE [fecha] = CONVERT(DATE, DATEADD(DAY, -1, GETDATE())) 
			  AND [databasename] = @DatabaseName
		)
		SELECT 
			@DatabaseName AS 'TopAvgDuration',
			DS.Objectname,
			DS.TotalAvgDuration 'AvgDuration10Days',
			isnull(LV.[Avg_Duration],0) 'Avg_Duration',
			isnull(LV.[Avg_Reads],0) 'Avg_Reads',
			isnull(LV.[Avg_Writes],0) 'Avg_Writes',
			isnull(LV.[Avg_CPU],0) 'Avg_CPU',
			isnull(LV.[RowCounts],0) 'RowCounts',
			isnull(LV.[Exec_Count],0) 'Exec_Count'
		FROM DurationSummary DS
		LEFT JOIN LatestValues LV ON DS.[objectname] = LV.[objectname] 

    END
	
	ELSE IF @QueryId = 13

	BEGIN
		-- 13. TopAvgDurationHist: Historico de Serntencias Top 10 con mayor promedio de duración
		WITH Top10AvgDuration AS (
			SELECT TOP 10 
				[objectname],
				AVG([avg_duration]) AS TotalAvgDuration
			FROM ExecutionSummaryLog
			WHERE [fecha] >= CONVERT(DATE, DATEADD(DAY, -10, GETDATE())) 
			  AND [databasename] = @DatabaseName
			GROUP BY [objectname]
			ORDER BY AVG([avg_duration])  DESC
		), DateRange AS (
			SELECT CAST(DATEADD(DAY, v.number - 10, GETDATE()) AS DATE) AS RecordDate
			FROM master..spt_values v
			WHERE v.type = 'P' AND v.number BETWEEN 0 AND 9
		)
		SELECT 
			@DatabaseName 'TopAvgDurationHist', 
			t.ObjectName, 
			dr.RecordDate, 
            isnull(h.[avg_duration],0) 'Avg_Duration',
            isnull(h.[Avg_Reads],0) 'Avg_Reads',
            isnull(h.[Avg_Writes],0) 'Avg_Writes',
            isnull(h.[Avg_CPU],0) 'Avg_CPU',
            isnull(h.[RowCounts],0) 'RowCounts',
            isnull(h.[Exec_Count],0) 'Exec_Count'
		FROM DateRange dr
		CROSS JOIN Top10AvgDuration t
		LEFT JOIN ExecutionSummaryLog h 
			ON dr.RecordDate = h.fecha
			AND t.objectname = h.objectname
		ORDER BY t.TotalAvgDuration DESC, t.objectname, dr.RecordDate DESC;
	END

	ELSE IF @QueryId = 14

	BEGIN
		-- 14. IdxFaltantes
		WITH IndexRecommendations AS (
			SELECT
				mid.database_id,
				mid.object_id,
				mid.index_handle,		
				OBJECT_SCHEMA_NAME(mid.object_id, mid.database_id) AS esquema,
				OBJECT_NAME(mid.object_id, mid.database_id) AS table_name,
				mid.equality_columns,
				mid.inequality_columns,
				mid.included_columns
			FROM
				sys.dm_db_missing_index_details AS mid
				JOIN sys.dm_db_missing_index_groups AS mig ON mid.index_handle = mig.index_handle
			WHERE mid.database_id = DB_ID(@DatabaseName) AND mid.included_columns IS NULL
		),
		IndexCosts AS (
			SELECT
				ir.database_id,
				ir.object_id,
				ir.esquema,
				ir.table_name,
				ir.equality_columns,
				ir.inequality_columns,
				ir.included_columns,
				'CREATE NONCLUSTERED INDEX IX_' 
				+ REPLACE(REPLACE(REPLACE(REPLACE(ir.table_name, '[', ''), ']', ''), ' ', '_'), ',', '_') 
				+ '_' 
				+ REPLACE(REPLACE(REPLACE(ISNULL(ir.equality_columns, ir.inequality_columns), '[', ''), ']', ''), ', ', '_') 
				+ ' ON ' 
				+ ir.esquema
				+ '.' 
				+ ir.table_name 
				+ ' (' 
				+ ISNULL(ir.equality_columns, '') 
				+ CASE 
					WHEN ir.equality_columns IS NOT NULL AND ir.inequality_columns IS NOT NULL 
					THEN ', ' 
					ELSE '' 
				  END 
				+ ISNULL(ir.inequality_columns, '') 
				+ ')' 
				+ CASE 
					WHEN ir.included_columns IS NOT NULL AND ir.included_columns <> '' 
					THEN ' INCLUDE (' 
					+ ir.included_columns 
					+ ')' 
					ELSE '' 
				  END AS create_index_statement,
				(CASE WHEN ir.equality_columns IS NOT NULL AND ir.equality_columns <> '' 
					  THEN LEN(ir.equality_columns) - LEN(REPLACE(ir.equality_columns, ',', '')) + 1
					  ELSE 0 
				 END
				 + CASE WHEN ir.inequality_columns IS NOT NULL AND ir.inequality_columns <> '' 
					  THEN LEN(ir.inequality_columns) - LEN(REPLACE(ir.inequality_columns, ',', '')) + 1
					  ELSE 0 
				 END
				 + CASE WHEN ir.included_columns IS NOT NULL AND ir.included_columns <> '' 
					  THEN LEN(ir.included_columns) - LEN(REPLACE(ir.included_columns, ',', '')) + 1
					  ELSE 0 
				 END
				) AS cost
			FROM
				IndexRecommendations AS ir
		),
		RankedIndexCosts AS (
			SELECT
				a.esquema,
				a.table_name,
				a.equality_columns,
				a.inequality_columns,
				a.create_index_statement,
				a.cost,
				CAST(ROUND(b.Reserved, 0) AS bigint) AS ReservedSpaceMB,
				ROW_NUMBER() OVER (
					PARTITION BY a.esquema, a.table_name,
								 CONCAT(ISNULL(a.equality_columns, ''), ISNULL(a.inequality_columns, ''))
					ORDER BY 
						LEN(CONCAT(ISNULL(a.equality_columns, ''), ISNULL(a.inequality_columns, ''))) DESC
				) AS rn
			FROM IndexCosts a
			INNER JOIN DatabaseTableSpaceUsage b 
				ON b.DatabaseName = @DatabaseName 
				AND b.RecordDate = CONVERT(DATE, GETDATE())  
				AND a.table_name = b.TableName
			WHERE a.cost < 6 AND b.Reserved > 10
		)
		SELECT 
			esquema,
			table_name,
			equality_columns,
			inequality_columns,
			create_index_statement,
			cost,
			ReservedSpaceMB
		FROM RankedIndexCosts
		WHERE rn = 1
		ORDER BY ReservedSpaceMB DESC;

	END
	
END