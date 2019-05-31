--====================================================================================================

use master
go

if object_id('dbo.install_tsqlt_tests') is not null
begin
    drop procedure dbo.install_tsqlt_tests
end
go

create procedure dbo.install_tsqlt_tests
(
     @database_name nvarchar(128)   -- [Required] The database where you want to install the tSQLt class
    ,@folder_path varchar(260)      -- [Required] Path to the folder containing the Tests (i.e., C:\Users\username\Documents\GitHub\repository-name\database\Tests)
    ,@debug tinyint = 0
)
as

/*

This will look at the database folder and install all the tests for that database type (e.g., Portal, Case).

*/

set nocount on
--set xact_abort on -- disabled on purpose.
--set transaction isolation level read uncommitted -- not necessary.

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] START'

declare
     @return int = 0
    ,@xp_cmdshell nvarchar(4000)
    ,@server_name nvarchar(128) = @@servername
    ,@file_path varchar(260)
    ,@test_class nvarchar(max)
    ,@rowcount int

declare @output table (test_class nvarchar(max) null)

create table #loadoutput (ident int not null identity(1, 1) primary key clustered, ret_code int, test_class nvarchar(1000), command_output nvarchar(max))

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] Running validate_path'

set @folder_path = dbo.directory_slash(null, @folder_path, '\')

-- Validate path
exec @return = master.dbo.validate_path
     @path = @folder_path
    ,@is_file = 0
    ,@is_directory = 1
    ,@debug = @debug

if @return <> 0
begin
    raiserror('Invalid path [%s].', 16, 1, @folder_path)
    return @return
end

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] Running validate_database'

-- Make sure the database exists, etc.
exec @return = master.dbo.validate_database
     @database_name = @database_name
    ,@debug = @debug

if @return <> 0 return @return -- The previous call will throw an error so don't bother throwing another.

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] Running install_tsqlt_class on ' + @database_name

set @file_path = dbo.directory_slash(null, @folder_path, '\') + 'tSQLt.Class.sql'

exec @return = master.dbo.install_tsqlt_class
     @database_name = @database_name
    ,@file_path = @file_path
    ,@debug = @debug

if @return <> 0 return @return -- The previous call will throw an error so don't bother throwing another.

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] Getting all of the test classes.'

set @xp_cmdshell = 'dir /b "' + @folder_path + '\*.sql"'

if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] @xp_cmdshell: ' + isnull(@xp_cmdshell, '{null}')

insert @output (test_class)
    exec xp_cmdshell @xp_cmdshell

delete @output where test_class is null or test_class like 'File Not Found%' -- Happens when you don't have any procedures in a folder

delete @output where test_class = 'tSQLt.Class.sql'

select @rowcount = count(*) from @output

if @debug >= 5 select '@output' as '@output', * from @output

if exists (select 1 from @output where test_class = N'The system cannot find the file specified.')
begin
    raiserror('The system cannot find the path specified. Make sure @path is correct.', 16, 1)
    return -1
end

if exists (select 1 from @output where test_class = N'The device is not ready.')
begin
    raiserror('The device is not ready. Make sure @path is pointing to the correct drive letter.', 16, 1)
    return -1
end

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] Found ' + ltrim(str(@rowcount)) + ' test classes.'

--====================================================================================================

if @rowcount > 0
begin
    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] Installing test classes on ' + @database_name

    if exists (select 1 from sys.databases where name = @database_name)
    begin
        while exists (select 1 from @output)
        begin
            select top 1 @test_class = test_class, @xp_cmdshell = null from @output

            -- TODO: Change this to use the list_files, read_file, clean_file, parse_file logic so that you can count the number of GOs and make sure that all of the test classes and individual tests got installed.
            select
                 -- If you add the -b switch (sqlcmd -b -E...) it will fail as soon as it runs into an error
                 @xp_cmdshell = 'sqlcmd -b -E -S "<<@server_name>>" -d "<<@database_name>>" -I -i "<<@folder_path>>\<<@test_class>>"'
                ,@xp_cmdshell = replace(@xp_cmdshell, '<<@server_name>>', @server_name)
                ,@xp_cmdshell = replace(@xp_cmdshell, '<<@database_name>>', @database_name)
                ,@xp_cmdshell = replace(@xp_cmdshell, '<<@folder_path>>', @folder_path)
                ,@xp_cmdshell = replace(@xp_cmdshell, '<<@test_class>>', @test_class)

            if @debug >= 5 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] @xp_cmdshell: ' + isnull(@xp_cmdshell, '{null}')

            if @debug >= 255
                exec @return = xp_cmdshell @xp_cmdshell
            else
                exec @return = xp_cmdshell @xp_cmdshell, 'no_output'

            if @return <> 0
            begin
                insert into #loadoutput (command_output)
                    exec xp_cmdshell @xp_cmdshell

                update #loadoutput
                    set ret_code = @return
                        ,test_class = @test_class
                    where ret_code is null
            end

            delete @output where test_class = @test_class

            if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] Finished installing ' + @test_class + ' on ' + @database_name
        end
    end

    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] Finished installing the test classes.'
end

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] END'

if exists (select 1 from #loadoutput)
    select ident, ret_code, test_class, command_output from #loadoutput where command_output is not null order by ident

return @return

go

/*

use Sandbox
go

exec master.dbo.upgrade_database
     @database_name = 'Sandbox'
    ,@folder_path = 'C:\Users\username\Documents\GitHub\repository-name\database\Tests'
    ,@debug = 1

exec master.dbo.install_tsqlt_tests
     @database_name = 'Sandbox'
    ,@folder_path = 'C:\Users\username\Documents\GitHub\repository-name\database'
    ,@debug = 1

-- Run all tSQLt tests
exec tSQLt.RunAll

*/

/*

-- Find the schema for any procedures that have "test" in the front and are not "dbo" and use tSQLt.DropClass to remove them.
-- Note: There's no easy way to find all of the tSQLt stored procedures because you can't assume that every non-dbo stored procedure is tSQLt. Someone could have created a stored procedure named "foo.bar".
-- A better method would be to restore a blank copy of the database and schema because someone could have created a real procedure named "foo.test-bar".
declare @sql nvarchar(4000) = N''

select @sql = @sql + 'exec tSQLt.DropClass ''' + schema_name([schema_id]) + '''
' from (select distinct [schema_id] from sys.procedures where is_ms_shipped = 0 and [schema_id] <> schema_id('dbo') and name like 'test%') x

exec sp_executesql @sql

*/

