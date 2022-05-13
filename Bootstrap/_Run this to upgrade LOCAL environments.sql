use master
go

/* IMPORTANT:

Make sure you have the correct Git branch checked out before you run this.
You should really only upgrade your database using 'master' or 'develop'.
But there's nothing stopping you from upgrading using a feature branch.
Just remember that the feature branch may have messed up your data and you might need to restore a clean database backup.

*/

/* Delete snapshot (optional)

use master

drop database [FMCSW_LOCAL_SS_20190524]

*/

/* Create snapshot (optional)

use master

create database [FMCSW_LOCAL_SS_20190903] on (name = FMCSW, filename = 'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Data\FMCSW_LOCAL_SS_20190903.ss') as snapshot of [FMCSW_LOCAL]

*/

/* Restore snapshot (optional)

use master

restore database [FMCSW_LOCAL] from database_snapshot = 'FMCSW_LOCAL_SS_20190903'

*/

/* DROP ALL SW TABLES AND VIEWS

use FMCSW_LOCAL
go

set nocount on

declare @schema_name sysname, @table_name sysname, @view_name sysname, @base nvarchar(4000), @sql nvarchar(4000)

declare @tables table ([schema_name] sysname not null, table_name sysname not null)

declare @views table ([schema_name] sysname not null, view_name sysname not null)

insert @tables ([schema_name], table_name)
    select schema_name(schema_id) as [schema_name], [name] as table_name
    from sys.tables
    where is_ms_shipped = 0
    and schema_id = schema_id('sw')
    and temporal_type <> 1
    order by name

--select * from @tables

insert @views ([schema_name], view_name)
    select schema_name(schema_id) as [schema_name], [name] as view_name
    from sys.views
    where is_ms_shipped = 0
    and schema_id = schema_id('sw')
    order by name

--select * from @views

set @base = '
if object_id(''[<<@schema_name>>].[<<@table_name>>History]'') is not null
begin
    if object_id(''[<<@schema_name>>].[<<@table_name>>]'') is not null
    and exists (select 1 from sys.tables where schema_id = schema_id(''<<@schema_name>>'') and [name] = ''<<@table_name>>'' and temporal_type = 2)
        alter table [<<@schema_name>>].[<<@table_name>>] set (system_versioning = off)

    if object_id(''[<<@schema_name>>].[<<@table_name>>History]'') is not null
        drop table [<<@schema_name>>].[<<@table_name>>History]
end

if object_id(''[<<@schema_name>>].[<<@table_name>>]'') is not null drop table [<<@schema_name>>].[<<@table_name>>]
'

while exists (select 1 from @tables)
begin
    select top (1) @schema_name = [schema_name], @table_name = table_name from @tables order by [schema_name], table_name

    set @sql = replace(@base, '<<@schema_name>>', @schema_name)
    set @sql = replace(@sql, '<<@table_name>>', @table_name)

    print @sql
    exec sp_executesql @sql

    delete @tables where table_name = @table_name
end

set @base = 'if object_id(''[<<@schema_name>>].[<<@view_name>>]'') is not null drop view [<<@schema_name>>].[<<@view_name>>]'

while exists (select 1 from @views)
begin
    select top (1) @schema_name = [schema_name], @view_name = view_name from @views order by [schema_name], view_name

    set @sql = replace(@base, '<<@schema_name>>', @schema_name)
    set @sql = replace(@sql, '<<@view_name>>', @view_name)

    print @sql
    exec sp_executesql @sql

    delete @views where view_name = @view_name
end
go

*/

declare @return int = 0

exec @return = master.dbo.upgrade_database
     @database_name = 'FMCSW_LOCAL' -- The name of your local database (e.g. FMCSW_LOCAL, FMCSW_DEV, ScheduleWise)
    ,@folder_path = 'C:\GitHub\fmc-schedulewise-database\FMCSW' -- Path to your database repository
    ,@folder_exclusions = 'Build,Bootstrap,Jobs,Roles,Scripts,Tests,Users'
    ,@file_exclusions = null
    ,@debug = 1

select @return as [return]
go
