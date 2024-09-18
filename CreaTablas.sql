USE [dbtools]
GO

CREATE TABLE [dbo].[UserPermissions](
	[Usuario] [nvarchar](128) NOT NULL,
	[BaseDatos] [nvarchar](128) NOT NULL,
	[TipoAcceso] [nvarchar](50) NULL,
	[FechaInicio] [datetime] NULL,
	[FechaFin] [datetime] NULL,
 CONSTRAINT [PK_UserPermissions] PRIMARY KEY CLUSTERED 
(
	[Usuario] ASC,
	[BaseDatos] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

USE [dbtools]
GO

CREATE TABLE [dbo].[RegisteredDatabases](
	[DatabaseName] [nvarchar](128) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[DatabaseName] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

USE [dbtools]
GO

CREATE TABLE [dbo].[LastInsertTime](
	[last_starttime] [datetime] NULL
) ON [PRIMARY]
GO

USE [dbtools]
GO

CREATE TABLE [dbo].[IndexRebuildAudit](
	[AuditID] [int] IDENTITY(1,1) NOT NULL,
	[DatabaseName] [nvarchar](128) NULL,
	[TableName] [nvarchar](128) NULL,
	[IndexName] [nvarchar](128) NULL,
	[SchemaName] [nvarchar](128) NULL,
	[RebuildDateTime] [datetime] NULL,
	[Status] [nvarchar](50) NULL,
	[ErrorMessage] [nvarchar](max) NULL,
PRIMARY KEY CLUSTERED 
(
	[AuditID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

USE [dbtools]
GO

CREATE TABLE [dbo].[IndexFragmentationHistory](
	[RecordDate] [date] NOT NULL,
	[DatabaseName] [nvarchar](128) NOT NULL,
	[TableName] [nvarchar](128) NOT NULL,
	[IndexName] [nvarchar](128) NOT NULL,
	[IndexType] [nvarchar](60) NOT NULL,
	[IndexID] [int] NOT NULL,
	[FragmentationPercent] [decimal](5, 2) NULL,
	[FragmentCount] [int] NULL,
	[AvgFragmentSizeInPages] [decimal](10, 2) NULL,
	[PageCount] [int] NULL,
	[SizeMB] [decimal](10, 2) NULL,
	[UserSeeks] [bigint] NULL,
	[UserScans] [bigint] NULL,
	[UserLookups] [bigint] NULL,
	[UserUpdates] [bigint] NULL,
	[LastUserSeek] [datetime] NULL,
	[LastUserScan] [datetime] NULL,
	[LastUserLookup] [datetime] NULL,
	[LastUserUpdate] [datetime] NULL,
	[ActionRequired] [nvarchar](20) NOT NULL
) ON [PRIMARY]
GO

USE [dbtools]
GO

CREATE TABLE [dbo].[ImpactedObjects](
	[DatabaseName] [nvarchar](100) NULL,
	[ObjectName] [nvarchar](100) NULL,
	[ObjectType] [nvarchar](50) NULL,
	[ImpactDetail] [nvarchar](max) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

USE [dbtools]
GO

CREATE TABLE [dbo].[ExecutionSummaryLog](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[fecha] [date] NULL,
	[objectname] [nvarchar](128) NULL,
	[application] [nvarchar](128) NULL,
	[databaseid] [int] NULL,
	[databasename] [nvarchar](128) NULL,
	[avg_duration] [float] NULL,
	[avg_reads] [float] NULL,
	[avg_writes] [float] NULL,
	[avg_cpu] [float] NULL,
	[rowcounts] [bigint] NULL,
	[exec_count] [bigint] NULL,
PRIMARY KEY NONCLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

USE [dbtools]
GO

CREATE TABLE [dbo].[ExecutionDetailsLog](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[textdata] [nvarchar](max) NULL,
	[application] [nvarchar](128) NULL,
	[databaseid] [int] NULL,
	[databasename] [nvarchar](128) NULL,
	[starttime] [datetime] NULL,
	[endtime] [datetime] NULL,
	[duration] [decimal](18, 2) NULL,
	[avg_duration] [decimal](18, 2) NULL,
	[reads] [bigint] NULL,
	[writes] [bigint] NULL,
	[cpu] [decimal](18, 2) NULL,
	[hostname] [nvarchar](128) NULL,
	[loginname] [nvarchar](128) NULL,
	[ntusername] [nvarchar](128) NULL,
	[objectname] [nvarchar](128) NULL,
	[rowcounts] [bigint] NULL,
	[servername] [nvarchar](128) NULL,
	[exec_count] [int] NULL,
	[insert_date] [datetime] NULL,
	[fecha] [date] NULL,
 CONSTRAINT [PK_ExecutionDetailsLog] PRIMARY KEY NONCLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

ALTER TABLE [dbo].[ExecutionDetailsLog] ADD  DEFAULT (getdate()) FOR [insert_date]
GO

ALTER TABLE [dbo].[ExecutionDetailsLog] ADD  CONSTRAINT [DF_ExecutionDetailsLog_fecha]  DEFAULT (CONVERT([date],getdate())) FOR [fecha]
GO

USE [dbtools]
GO

CREATE TABLE [dbo].[DatabaseTableSpaceUsage](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[DatabaseSpaceUsageId] [int] NULL,
	[DatabaseName] [nvarchar](128) NULL,
	[SchemaName] [nvarchar](128) NULL,
	[TableName] [nvarchar](128) NULL,
	[NumRows] [decimal](18, 0) NULL,
	[Reserved] [decimal](18, 2) NULL,
	[Used] [decimal](18, 2) NULL,
	[Unused] [decimal](18, 2) NULL,
	[RecordDateTime] [datetime] NULL,
	[RecordDate] [date] NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[DatabaseTableSpaceUsage]  WITH CHECK ADD FOREIGN KEY([DatabaseSpaceUsageId])
REFERENCES [dbo].[DatabaseSpaceUsage] ([ID])
GO

USE [dbtools]
GO

CREATE TABLE [dbo].[DatabaseSpaceUsage](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[DatabaseName] [nvarchar](128) NULL,
	[DatabaseSize] [decimal](18, 2) NULL,
	[UnallocatedSpace] [decimal](18, 2) NULL,
	[Reserved] [decimal](18, 2) NULL,
	[DataSize] [decimal](18, 2) NULL,
	[IndexSize] [decimal](18, 2) NULL,
	[Unused] [decimal](18, 2) NULL,
	[LogUsed] [decimal](18, 2) NULL,
	[LogUnused] [decimal](18, 2) NULL,
	[RecordDateTime] [datetime] NULL,
	[RecordDate] [date] NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

USE [dbtools]
GO

CREATE TABLE [dbo].[DatabaseAssessment](
	[ServerName] [nvarchar](100) NULL,
	[DatabaseName] [nvarchar](100) NULL,
	[CompatibilityLevel] [nvarchar](50) NULL,
	[SizeMB] [decimal](18, 2) NULL,
	[Status] [nvarchar](50) NULL,
	[ServerVersion] [nvarchar](100) NULL,
	[ServerEdition] [nvarchar](100) NULL
) ON [PRIMARY]
GO

USE [dbtools]
GO

CREATE TABLE [dbo].[ConfiguracionArchivos](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[NombreBD] [nvarchar](128) NULL,
	[NombreTabla] [nvarchar](128) NULL,
	[ColumnaFiltro] [nvarchar](128) NULL,
	[MesesARetener] [int] NULL,
	[TamanoMinimoTablaMB] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
