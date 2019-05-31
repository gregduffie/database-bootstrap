--====================================================================================================

use master
go

if object_id('dbo.get_default_database_location') is not null
begin
    drop procedure dbo.get_default_database_location
end
go

create procedure dbo.get_default_database_location
(
     @default_data_path nvarchar(1000) = null output
    ,@default_log_path nvarchar(1000) = null output
    ,@debug tinyint = 0
)
with encryption
as

set nocount on
set xact_abort on
set transaction isolation level read uncommitted

/* Borrowed and modified from: http://www.dbi-services.com/index.php/blog/entry/sql-server-how-to-find-default-data-path */

/* Suggested @debug values
1 = Simple print statements
2 = Simple select statements (e.g. select @variable_1 as variable_1, @variable_2 as variable_2)
3 = Result sets from temp tables (e.g. select '#temp_table_name' as '#temp_table_name' from #temp_table_name where ...)
4 = @sql statements from exec() or sp_executesql
*/

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [get_default_database_location] START'

declare
     @position int
    ,@instance_name nvarchar(128)
    ,@registry_path nvarchar(128)
    ,@registry_key nvarchar(max)
    ,@database_name nvarchar(128)
    ,@sql nvarchar(1000)
    ,@sql_params nvarchar(200)

create table #instance_registry_path
(
     instance_name nvarchar(128)
    ,registry_path nvarchar(128)
)

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [get_default_database_location] Trying SERVERPROPERTY method'

-- If SQL Server 2012...
select
     @default_data_path = convert(nvarchar(128), serverproperty('instancedefaultdatapath'))
    ,@default_log_path = convert(nvarchar(128), serverproperty('instancedefaultlogpath'))

if @default_data_path is null
begin
    /* Must be SQL Server 2005 through 2008 */

    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [get_default_database_location] Trying registry method'

    -- Get the instance name
    set @position = charindex('\', @@servername)

    if @position = 0
        set @instance_name = N'MSSQLSERVER'
    else
        set @instance_name = substring(@@servername, @position + 1, len(@@servername))

    -- Pull the default path from the registry
    insert #instance_registry_path
        exec master.sys.xp_instance_regenumvalues N'HKEY_LOCAL_MACHINE', N'SOFTWARE\\Microsoft\\Microsoft SQL Server\\Instance Names\\SQL'

    select @registry_path = registry_path from #instance_registry_path where @instance_name = instance_name

    set @registry_key = N'SOFTWARE\Microsoft\Microsoft SQL Server\' + @registry_path + N'\MSSQLServer'

    exec master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @registry_key, N'DefaultData', @default_data_path output
    exec master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @registry_key, N'DefaultLog', @default_log_path output

    if @default_data_path is null
    begin
        /* Wow, either something's *really* wrong or you're using a very old version of SQL Server! */

        if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [get_default_database_location] Trying any user database method'

        -- Look for the most recent, non-system database and see what they are using.
        select top 1 @database_name = name from sys.databases where database_id > 4 and name not in ('ReportServer', 'ReportServerTempDB') order by create_date desc

        if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [get_default_database_location] Getting physical_name from database [' + @database_name + ']'

        select
             @sql_params = N'@default_data_path nvarchar(1000) output, @default_log_path nvarchar(1000) output'
            ,@sql = N'select top 1 @default_data_path = physical_name from [<<@database_name>>].sys.database_files where type = 0; select top 1 @default_log_path = physical_name from [<<@database_name>>].sys.database_files where type = 1;'
            ,@sql = replace(@sql, '<<@database_name>>', @database_name)

        exec sp_executesql
             @sql, @sql_params
            ,@default_data_path = @default_data_path output
            ,@default_log_path = @default_log_path output

        if @default_data_path is null
        begin
            /* I guess we'll just use master. And if you don't have THAT then I'm out. */

            if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [get_default_database_location] Trying master database method'

            select
                 @sql_params = N'@default_data_path nvarchar(1000) output, @default_log_path nvarchar(1000) output'
                ,@sql = N'select top 1 @default_data_path = physical_name from [master].sys.database_files where type = 0; select top 1 @default_log_path = physical_name from [master].sys.database_files where type = 1;'

            exec sp_executesql
                 @sql, @sql_params
                ,@default_data_path = @default_data_path output
                ,@default_log_path = @default_log_path output
        end

        select
             @default_data_path = reverse(stuff(reverse(@default_data_path), 1, charindex('\', reverse(@default_data_path)), ''))
            ,@default_log_path = reverse(stuff(reverse(@default_log_path), 1, charindex('\', reverse(@default_log_path)), ''))
    end
end

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [get_default_database_location] END'

return 0

go

/* DEV TESTING

declare
     @default_data_path nvarchar(1000)
    ,@default_log_path nvarchar(1000)
    ,@debug tinyint = 9

exec master.dbo.get_default_database_location
     @default_data_path = @default_data_path output
    ,@default_log_path = @default_log_path output
    ,@debug = @debug

select @default_data_path as default_data_path, @default_log_path as default_log_path

*/

