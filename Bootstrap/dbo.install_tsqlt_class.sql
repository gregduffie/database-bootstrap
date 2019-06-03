--====================================================================================================

use master
go

if object_id('dbo.install_tsqlt_class') is not null
begin
    drop procedure dbo.install_tsqlt_class
end
go

create procedure dbo.install_tsqlt_class
(
     @database_name nvarchar(128)       -- [Required] The database where you want to install the tSQLt class
    ,@file_path varchar(260)            -- [Required] Full path to the tSQLt.class.sql file
    ,@debug tinyint = 0
)
with encryption
as

/*

This will check for and install the tSQLt class to your database.

*/

set nocount on
--set xact_abort on -- disabled on purpose.
--set transaction isolation level read uncommitted -- not necessary.

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] START'

declare
     @return int = 0
    ,@sql nvarchar(1000)
    ,@sql_params nvarchar(100)
    ,@tsqlt_version_installed varchar(14)
    ,@tsqlt_version_release varchar(14)
    ,@xp_cmdshell nvarchar(4000)
    ,@server_name nvarchar(128) = @@servername
    ,@file_content nvarchar(max)
    ,@pos int
    ,@is_file bit

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] Running validate_path'

-- Validate path
exec @return = master.dbo.validate_path
     @path = @file_path
    ,@is_file = @is_file output
    ,@debug = @debug

if @is_file = 0
begin
    raiserror('Invalid path [%s].', 16, 1, @file_path)
    return @return
end

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] Running validate_database'

-- Make sure the database exists, etc.
exec @return = master.dbo.validate_database
     @database_name = @database_name
    ,@debug = @debug

if @return <> 0 return @return -- The previous call will throw an error so don't bother throwing another.

--====================================================================================================

-- This fixes a problem with restored databases and the tSQLt Class. Assumes that SA exists.

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] Changing owner of database to sa'

select
     @sql = N'alter authorization on database::[<<@database_name>>] to sa;'
    ,@sql = replace(@sql, '<<@database_name>>', @database_name)

if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] @sql: ' + isnull(@sql, '{null}')

exec @return = sp_executesql @sql

if @return <> 0 return @return

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] Setting trustworthy on'

select
     @sql = N'alter database [<<@database_name>>] set trustworthy on;'
    ,@sql = replace(@sql, '<<@database_name>>', @database_name)

if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] @sql: ' + isnull(@sql, '{null}')

exec @return = sp_executesql @sql

if @return <> 0 return @return

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] Get installed version number on [' + @database_name + ']'

select
     @sql_params = N'@tsqlt_version_installed varchar(14) output'
    ,@sql = N'if exists (select 1 from [<<@database_name>>].sys.schemas where name = ''tSQLt'') select @tsqlt_version_installed = [Version] from [<<@database_name>>].tSQLt.Info() else set @tsqlt_version_installed = 0'
    ,@sql = replace(@sql, '<<@database_name>>', @database_name)

if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] @sql: ' + isnull(@sql, '{null}')

-- Have to use Dynamic SQL because the database name could be different from the current database
exec @return = sp_executesql @sql, @sql_params, @tsqlt_version_installed = @tsqlt_version_installed output

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] @tsqlt_version_installed: ' + isnull(@tsqlt_version_installed, '{null}')

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] Get release version number'

exec master.dbo.read_file
     @file_path = @file_path
    ,@file_content = @file_content output
    ,@debug = @debug

-- Look for the version number/pattern
select @pos = patindex('%Version = ''[0-9].[0-9].%', @file_content)

if @pos > 0
    select @tsqlt_version_release = substring(@file_content, @pos + 11, 14)
else
    select @tsqlt_version_release = '0'

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] @tsqlt_version_release: ' + isnull(@tsqlt_version_release, '{null}')

--====================================================================================================

if @tsqlt_version_installed = '0' or (convert(bigint, replace(@tsqlt_version_release, '.', '')) > convert(bigint, replace(@tsqlt_version_installed, '.', '')))
begin
    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] Installing tSQLt.class.sql on [' + @database_name + ']'

    -- TODO: Change this to use the list_files, read_file, clean_file, parse_file logic so that you can count the number of GOs and make sure that all of the test classes and individual tests got installed.
    select
         -- If you add the -b switch (sqlcmd -b -E...) it will fail as soon as it runs into an error
         @xp_cmdshell = 'sqlcmd -E -S "<<@server_name>>" -d "<<@database_name>>" -I -i "<<@file_path>>"'
        ,@xp_cmdshell = replace(@xp_cmdshell, '<<@server_name>>', @server_name)
        ,@xp_cmdshell = replace(@xp_cmdshell, '<<@database_name>>', @database_name)
        ,@xp_cmdshell = replace(@xp_cmdshell, '<<@file_path>>', @file_path)

    if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] @xp_cmdshell: ' + isnull(@xp_cmdshell, '{null}')

    if @debug >= 255
        exec xp_cmdshell @xp_cmdshell
    else
        exec xp_cmdshell @xp_cmdshell, no_output

    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] Finished installing tSQLt.class.sql on [' + @database_name + ']'
end

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] END'

return @return

go

/*

use Sandbox
go

exec master.dbo.install_tsqlt_tests
     @database_name = 'Sandbox'
    ,@folder_path = 'C:\Users\username\Documents\GitHub\repository-name\database\Tests'
    ,@debug = 6

exec master.dbo.install_tsqlt_class
     @database_name = 'Sandbox'
    ,@file_path = 'C:\Users\username\Documents\GitHub\repository-name\Database\Tests\tSQLt.class.sql'
    ,@debug = 6

*/

