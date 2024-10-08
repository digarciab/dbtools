USE [dbtools]
GO
/****** Object:  StoredProcedure [dbo].[InsertExecutionDetails]    Script Date: 24/09/2024 11:29:27 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER   PROCEDURE [dbo].[InsertExecutionDetails]
AS
BEGIN
    DECLARE @last_insert_time DATETIME, @now_time DATETIME;

    -- Obtener la última fecha y hora de inserción
    SELECT @last_insert_time = last_starttime, @now_time = GETDATE() FROM LastInsertTime;

    -- Insertar la fecha y hora de inserción
    IF @last_insert_time IS NULL
    BEGIN        
        INSERT INTO LastInsertTime(last_starttime) VALUES ('1900-01-01');
        SELECT @last_insert_time = '1900-01-01';
    END

    -- Declarar la variable de tabla para almacenar los resultados
    DECLARE @ExecutionDetails TABLE (
        textdata NVARCHAR(MAX),
        application NVARCHAR(128),
        databaseid INT,
        databasename NVARCHAR(128),
        starttime DATETIME,
        endtime DATETIME,
        duration_seconds DECIMAL(18,2),
        avg_duration_seconds DECIMAL(18,2),
        reads BIGINT,
        writes BIGINT,
        cpu_seconds DECIMAL(18,2),
        hostname NVARCHAR(128),
        loginname NVARCHAR(128),
        ntusername NVARCHAR(128),
        objectname NVARCHAR(128),
        rowcounts BIGINT,
        servername NVARCHAR(128),
        exec_count INT
    );

    -- Insertar los nuevos registros desde la última inserción en la variable de tabla
    INSERT INTO @ExecutionDetails(
        textdata,
        application,
        databaseid,
        databasename,
        starttime,
        endtime,
        duration_seconds,
        avg_duration_seconds,
        cpu_seconds,
        reads,
        writes,
        rowcounts,
        objectname,       
		servername,
        hostname,
        loginname,
        ntusername,
        exec_count
    )
    SELECT 
        st.text AS textdata,
        s.program_name AS application, 
        st.dbid AS databaseid,
        DB_NAME(st.dbid) AS databasename,
        qs.last_execution_time AS starttime,
        CASE 
            WHEN qs.total_elapsed_time <= 2147483647 
            THEN DATEADD(MILLISECOND, CAST(qs.total_elapsed_time/1000 AS BIGINT), qs.last_execution_time)
            ELSE NULL
        END AS endtime,
        CASE 
            WHEN qs.total_elapsed_time <= 2147483647
            THEN CAST(qs.total_elapsed_time AS DECIMAL(18,2)) / 1000.0
            ELSE NULL
        END AS duration_seconds,
        CASE 
            WHEN qs.execution_count = 0 OR qs.total_elapsed_time > 2147483647 
            THEN NULL
            ELSE CAST((qs.total_elapsed_time / NULLIF(qs.execution_count, 0)) AS DECIMAL(18,2)) / 1000.0
        END AS avg_duration_seconds,
        CASE 
            WHEN qs.total_worker_time <= 2147483647
            THEN CAST(qs.total_worker_time AS DECIMAL(18,2)) / 1000.0
            ELSE NULL
        END AS cpu_seconds,
        CASE 
            WHEN qs.total_logical_reads <= 2147483647
            THEN TRY_CAST(qs.total_logical_reads AS BIGINT)
            ELSE NULL
        END AS reads,
        CASE 
            WHEN qs.total_logical_writes <= 2147483647
            THEN TRY_CAST(qs.total_logical_writes AS BIGINT)
            ELSE NULL
        END AS writes,
        CASE 
            WHEN qs.total_rows <= 2147483647
            THEN TRY_CAST(qs.total_rows AS BIGINT)
            ELSE NULL
        END AS rowcounts,
        COALESCE(OBJECT_NAME(st.objectid, st.dbid), '') AS objectname,
        @@SERVERNAME AS servername,
        s.host_name AS hostname,
        s.login_name AS loginname,
        s.nt_user_name AS ntusername,
        qs.execution_count AS exec_count
    FROM sys.dm_exec_query_stats AS qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
    LEFT JOIN sys.dm_exec_requests AS r ON qs.plan_handle = r.plan_handle
    LEFT JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
    WHERE st.dbid > 4
        AND st.dbid IS NOT NULL
		AND qs.last_execution_time > @last_insert_time
        AND qs.last_execution_time < @now_time
		AND CASE 
                WHEN qs.execution_count = 0 OR qs.total_elapsed_time > 2147483647 
                    THEN NULL
                ELSE CAST((qs.total_elapsed_time / NULLIF(qs.execution_count, 0)) AS DECIMAL(18,2)) / 1000.0
            END >= 1000
	union
	SELECT 
		st.text AS textdata,
		s.program_name AS application,
		st.dbid AS databaseid,
		DB_NAME(st.dbid) AS databasename,
		qs.creation_time AS starttime,
		CASE 
			WHEN qs.total_elapsed_time <= 2147483647 
			THEN DATEADD(MILLISECOND, CAST(qs.total_elapsed_time / 1000 AS BIGINT), qs.creation_time)
			ELSE NULL
		END AS endtime,
		CASE 
			WHEN qs.total_elapsed_time <= 2147483647 
			THEN CAST(qs.total_elapsed_time AS DECIMAL(18, 2)) / 1000.0
			ELSE NULL
		END AS duration_seconds,
		CASE 
			WHEN qs.execution_count = 0 OR qs.total_elapsed_time > 2147483647 
			THEN NULL
			ELSE CAST((qs.total_elapsed_time / NULLIF(qs.execution_count, 0)) AS DECIMAL(18, 2)) / 1000.0
		END AS avg_duration_seconds,
		CASE 
			WHEN qs.total_worker_time <= 2147483647 
			THEN CAST(qs.total_worker_time AS DECIMAL(18, 2)) / 1000.0
			ELSE NULL
		END AS cpu_seconds,
		CASE 
			WHEN qs.total_logical_reads <= 2147483647 
			THEN TRY_CAST(qs.total_logical_reads AS BIGINT)
			ELSE NULL
		END AS reads,
		CASE 
			WHEN qs.total_logical_writes <= 2147483647 
			THEN TRY_CAST(qs.total_logical_writes AS BIGINT)
			ELSE NULL
		END AS writes,
		CASE 
			WHEN qs.total_rows <= 2147483647 
			THEN TRY_CAST(qs.total_rows AS BIGINT)
			ELSE NULL
		END AS rowcounts,
		COALESCE(OBJECT_NAME(st.objectid, st.dbid), 'Ad-hoc Query') AS objectname,
		@@SERVERNAME AS servername,
		s.host_name AS hostname,
		s.login_name AS loginname,
		s.nt_user_name AS ntusername,
		qs.execution_count AS exec_count
	FROM sys.dm_exec_cached_plans AS cp
	CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
	LEFT JOIN sys.dm_exec_query_stats AS qs ON cp.plan_handle = qs.plan_handle
	LEFT JOIN sys.dm_exec_requests AS r ON qs.plan_handle = r.plan_handle
	LEFT JOIN sys.dm_exec_sessions AS s ON r.session_id = s.session_id
	WHERE cp.objtype = 'Adhoc'
	  AND st.dbid > 4
	  AND st.dbid IS NOT NULL
	  AND qs.last_execution_time > @last_insert_time
      AND qs.last_execution_time < @now_time
	  AND CASE 
			WHEN qs.execution_count = 0 OR qs.total_elapsed_time > 2147483647 
				THEN NULL
			ELSE CAST((qs.total_elapsed_time / NULLIF(qs.execution_count, 0)) AS DECIMAL(18,2)) / 1000.0
		  END >= 1000;

    -- Insertar los registros en la tabla final
    INSERT INTO ExecutionDetailsLog (
        textdata,
        application,
        databaseid,
        databasename,
        starttime,
        endtime,
        duration,
        avg_duration,
        reads,
        writes,
        cpu,
        hostname,
        loginname,
        ntusername,
        objectname,
        rowcounts,
        servername,
        exec_count
    )
    SELECT 
        textdata,
        application,
        databaseid,
        databasename,
        starttime,
        endtime,
        duration_seconds AS duration,
        avg_duration_seconds AS avg_duration,
        reads,
        writes,
        cpu_seconds AS cpu,
        hostname,
        loginname,
        ntusername,
        objectname,
        rowcounts,
        servername,
        exec_count
    FROM @ExecutionDetails;

    -- Actualizar la última fecha y hora de inserción
    IF @@ROWCOUNT > 0
    BEGIN
        UPDATE LastInsertTime SET last_starttime = @now_time;
    END
END;
