--====================================================================================================

use master
go

if object_id('dbo.backup_database') is not null
begin
    drop procedure dbo.backup_database
end
go

create procedure dbo.backup_database
(
     @database_name nvarchar(128)       -- [Required] Actual database name that you are backing up (e.g., Database).
    ,@full_path nvarchar(4000)  = null  -- [Optional] The full path to the .bak file (e.g., D:\SQL\Backups\Database.bak). If not supplied we will use the default.
    ,@overwrite bit = 0                 -- [Optional] If a backup exists with the same name, Overwrite = 0 will append this backup to that one otherwise it will overwrite it.
    ,@name nvarchar(128) = null         -- [Optional] Name of the backup set. This is what you see in the SSMS UI.
    ,@description nvarchar(255) = null  -- [Optional] Describes the backup set. This is NOT seen in the SSMS UI.
    ,@debug tinyint = 0
)
with encryption
as

set nocount on
set xact_abort on
set transaction isolation level read uncommitted

/* Suggested @debug values
1 = Simple print statements
2 = Simple select statements (e.g. select @variable_1 as variable_1, @variable_2 as variable_2)
3 = Result sets from temp tables (e.g. select '#temp_table_name' as '#temp_table_name' from #temp_table_name where ...)
4 = @sql statements from exec() or sp_executesql
*/

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [backup_database] START'

declare
     @return int = 0
    ,@sql nvarchar(1000)
    ,@sql_params nvarchar(100)
    ,@app_version nvarchar(25)
    ,@db_version nvarchar(25)
    ,@directory nvarchar(4000) -- Directory only

--====================================================================================================

if not exists (select 1 from sys.databases where name = @database_name)
begin
    set @return = -1
    raiserror('Database [%s] does not exist on this server.', 16, 1, @database_name)
    return @return
end

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [backup_database] Getting app and db version numbers on database [' + @database_name + ']'

select
     @sql_params = N'@app_version nvarchar(25) output, @db_version nvarchar(25) output'
    ,@sql = N'
    use [<<@database_name>>]
    if exists (select 1 from dbo.ApplicationVariables)
    begin
        select @app_version = ltrim(rtrim(thevalue)) from dbo.ApplicationVariables where thelabel = ''ApplicationVersion'';
        select @db_version = ltrim(rtrim(thevalue)) from dbo.ApplicationVariables where thelabel = ''DatabaseVersion'';
    end
    '
    ,@sql = replace(@sql, '<<@database_name>>', @database_name)

if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [backup_database] @sql: ' + isnull(@sql, '{null}')

exec sp_executesql
     @sql, @sql_params
    ,@app_version = @app_version output
    ,@db_version = @db_version output

if @debug >= 2
begin
    print '[' + convert(varchar(23), getdate(), 121) + '] [backup_database] @app_version: ' + isnull(@app_version, '{null}')
    print '[' + convert(varchar(23), getdate(), 121) + '] [backup_database] @db_version: ' + isnull(@db_version, '{null}')
end

--====================================================================================================

-- Create strings

select
     @name = case when datalength(@name) > 0 then @name + N' - ' else N'' end
    ,@name = @name + N'App (<<@app_version>>); DB (<<@db_version>>)'
    ,@name = replace(@name, '<<@app_version>>', @app_version)
    ,@name = replace(@name, '<<@db_version>>', @db_version)

    ,@description = case when datalength(@description) > 0 then @description + N' - ' else N'' end
    ,@description = @description + N'Date (<<@date>>); Server (<<@server>>)'
    ,@description = replace(@description, '<<@date>>', convert(varchar(23), getdate(), 121))
    ,@description = replace(@description, '<<@server>>', @@servername)

if @debug >= 2
begin
    print '[' + convert(varchar(23), getdate(), 121) + '] [backup_database] @name: ' + isnull(@name, '{null}')
    print '[' + convert(varchar(23), getdate(), 121) + '] [backup_database] @description: ' + isnull(@description, '{null}')
end

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [backup_database] Validating backup path'

if nullif(@full_path, '') is null -- The .bak name wasn't supplied either
begin
    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [backup_database] @full_path was empty. Checking registry for default location.'

    exec master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'BackupDirectory', @directory output, 'no_output'

    -- Now add @database_name and .bak to the @full_path
    set @full_path = @directory + N'\' + @database_name + N'.bak'
end
else
begin
    -- Remove the database name and extension (since they won't exist on the first backup) and just validate the directory. If @full_path wasn't supplied then this step isn't necessary.
    set @directory = substring(@full_path, 1, len(@full_path) - charindex('\', reverse(@full_path)))
end

exec @return = master.dbo.rp_validate_path
     @path = @directory
    ,@debug = @debug

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [backup_database] Backing up database [' + @database_name + '] to ' + @full_path

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [backup_database] Backing up database [' + @database_name + ']'

select
     @sql = 'BACKUP DATABASE [<<@database_name>>] TO DISK = N''<<@full_path>>'' WITH DESCRIPTION = N''<<@description>>'', NOFORMAT, <<@init_noinit>>,  NAME = N''<<@name>>'', SKIP, NOREWIND, NOUNLOAD, STATS = 10'
    ,@sql = replace(@sql, '<<@database_name>>', @database_name)
    ,@sql = replace(@sql, '<<@full_path>>', @full_path)
    ,@sql = replace(@sql, '<<@description>>', @description)
    ,@sql = replace(@sql, '<<@init_noinit>>', case @overwrite when 1 then 'INIT' else 'NOINIT' end)
    ,@sql = replace(@sql, '<<@name>>', @name)

if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [backup_database] @sql: ' + isnull(@sql, '{null}')

exec sp_executesql @sql

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [backup_database] END'

return @return

go

grant exec on dbo.backup_database to public
go

/* DEV TESTING

-- Backup Database to "foo.bak"
exec master.dbo.backup_database
     @database_name = 'Database'
    ,@full_path = 'D:\SQL\Backup\foo.bak'
    ,@overwrite = 0
    ,@name = N'Database'
    ,@description = N'Backup Database to foo'
    ,@debug = 3

-- Restore "foo.bak" as "asfubjghhaifuvbh"
exec master.dbo.rp_case_restore
     @database_name = 'asfubjghhaifuvbh'
    ,@full_path = 'D:\SQL\Backup\foo.bak'
    ,@debug = 3

-- Drop "asfubjghhaifuvbh"
exec master.dbo.rp_case_drop
     @database_name = 'asfubjghhaifuvbh'
    ,@debug = 3

*/

