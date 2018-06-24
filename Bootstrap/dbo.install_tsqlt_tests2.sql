--====================================================================================================

use master
go

if object_id('dbo.install_tsqlt_tests2') is not null
begin
    drop procedure dbo.install_tsqlt_tests2
end
go

create procedure dbo.install_tsqlt_tests2
(
     @database_name nvarchar(128)   -- [Required] The database where you want to install the tSQLt class
    ,@folder_path varchar(260)             -- [Required] Path to the folder above the database folder (i.e., C:\Users\gduffie\Documents\GitHub\fmc-schedulewise)
    ,@debug tinyint = 0
)
as

/*

This will look at the database folder and install all the tests for that database type (e.g., Portal, Case).

*/

set nocount on
--set xact_abort on -- disabled on purpose.
--set transaction isolation level read uncommitted -- not necessary.

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests2] START'

declare
     @return int = 0
    ,@xp_cmdshell nvarchar(4000)
    ,@server_name nvarchar(128) = @@servername
    ,@file_path varchar(260)
    ,@test_class nvarchar(max)
    ,@count int

declare @output table (test_class nvarchar(max) null)

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests2] Running validate_path'

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

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests2] Running validate_database'

-- Make sure the database exists, etc.
exec @return = master.dbo.validate_database
     @database_name = @database_name
    ,@debug = @debug

if @return <> 0 return @return -- The previous call will throw an error so don't bother throwing another.

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests2] Running install_tsqlt_class on ' + @database_name

set @file_path = dbo.directory_slash(null, @folder_path, '\') + 'tSQLt.Class.sql'

exec @return = master.dbo.install_tsqlt_class
     @database_name = @database_name
    ,@file_path = @file_path
    ,@debug = @debug

if @return <> 0 return @return -- The previous call will throw an error so don't bother throwing another.

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests2] Getting all of the test procedures.'

set @xp_cmdshell = 'dir /b "' + @folder_path + '\*.sql"'

if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests2] @xp_cmdshell: ' + isnull(@xp_cmdshell, '{null}')

insert @output (test_class)
    exec xp_cmdshell @xp_cmdshell

delete @output where test_class is null or test_class like 'File Not Found%' -- Happens when you don't have any procedures in a folder

select @count = count(*) from @output

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

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests2] Found ' + ltrim(str(@count)) + ' test procedures.'

--====================================================================================================

if @count > 0
begin
    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests2] Installing test procedures on ' + @database_name

    if exists (select 1 from sys.databases where name = @database_name)
    begin
        while exists (select 1 from @output)
        begin
            select top 1 @test_class = test_class, @xp_cmdshell = null from @output

            select
                 @xp_cmdshell = 'sqlcmd -E -S "<<@server_name>>" -d "<<@database_name>>" -I -i "<<@path>>\<<@test_class>>"'
                ,@xp_cmdshell = replace(@xp_cmdshell, '<<@server_name>>', @server_name)
                ,@xp_cmdshell = replace(@xp_cmdshell, '<<@database_name>>', @database_name)
                ,@xp_cmdshell = replace(@xp_cmdshell, '<<@path>>', @folder_path)
                ,@xp_cmdshell = replace(@xp_cmdshell, '<<@test_class>>', @test_class)

            if @debug >= 5 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests2] @xp_cmdshell: ' + isnull(@xp_cmdshell, '{null}')

            if @debug >= 255
                exec xp_cmdshell @xp_cmdshell
            else
                exec xp_cmdshell @xp_cmdshell, 'no_output'

            delete @output where test_class = @test_class

            if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests2] Finished installing ' + @test_class + ' on ' + @database_name
        end
    end

    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests2] Finished installing the test procedures.'
end

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests2] END'

return @return

go

/*

use ScheduleWise
go

exec master.dbo.install_tsqlt_tests2
     @database_name = 'ScheduleWise'
    ,@folder_path = 'C:\Users\gduffie\Documents\GitHub\fmc-schedulewise\database\Tests'
    ,@debug = 2

-- Run all tSQLt tests
exec tSQLt.RunAll

*/
