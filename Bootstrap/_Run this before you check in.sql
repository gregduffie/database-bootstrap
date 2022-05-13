use master
go

set nocount on

declare
     @return int = 0
    ,@sql nvarchar(1000)
    ,@test_database_name nvarchar(128) = 'FMCSW_tSQLt'
    ,@full_path_to_tsqlt_backup nvarchar(128) = 'C:\GitHub\fmc-schedulewise-database\FMCSW\Tests\FMCSW_tSQLt.bak'
    ,@folder_path nvarchar(128) = 'C:\GitHub\fmc-schedulewise-database\FMCSW'
    ,@test_folder_path nvarchar(128)
    ,@message varchar(100)
    ,@debug tinyint = 0 -- Don't use anything other than 1 unless you know what you're doing and want to see a TON of output.

set @test_folder_path = @folder_path + '\Tests'

-- Restore Test Database
exec @return = master.dbo.restore_database
     @database_name = @test_database_name
    ,@file_path = @full_path_to_tsqlt_backup
    ,@debug = @debug

if @return <> 0 return

-- Upgrade Test Database
exec @return = master.dbo.upgrade_database
     @database_name = @test_database_name
    ,@folder_path = @folder_path
    ,@folder_exclusions = 'Build,Bootstrap,Jobs,Roles,Scripts,Tests,Users'
    ,@file_exclusions = null
    ,@debug = @debug

if @return <> 0 return

-- Upgrade Test Database again to make sure things don't break since the tSQLt database doesn't have much in it
exec @return = master.dbo.upgrade_database
     @database_name = @test_database_name
    ,@folder_path = @folder_path
    ,@folder_exclusions = 'Build,Bootstrap,Jobs,Roles,Scripts,Tests,Users'
    ,@file_exclusions = null
    ,@debug = @debug

if @return <> 0 return

-- Install tSQLt tests on Test Database
exec @return = master.dbo.install_tsqlt_tests
     @database_name = @test_database_name
    ,@folder_path = @test_folder_path
    ,@debug = @debug

if @return <> 0 return

-- Run all tSQLt tests on Test Database
set @sql = 'use [<<@test_database_name>>]; exec tSQLt.RunAll; select ''tSQLt.TestResult'' as ''tSQLt.TestResult Failures'', * from tSQLt.TestResult where Result <> ''Success'';'
set @sql = replace(@sql, '<<@test_database_name>>', @test_database_name)
--print @sql

exec sys.sp_executesql @sql

if cast(serverproperty('Edition') as nvarchar(128)) like N'Developer Edition%'
begin
    set @sql = 'use [<<@test_database_name>>]; select @messageOUT = ''tSQLt executed '' + convert(varchar(11), count(*)) + '' tests in '' + convert(varchar(11), datediff(second, min(TestStartTime), max(TestEndTime))) + '' seconds.'' from tSQLt.TestResult;'
    set @sql = replace(@sql, '<<@test_database_name>>', @test_database_name)
    exec sys.sp_executesql @sql, N'@messageOUT varchar(255) output', @messageOUT = @message OUTPUT
    print @message
end

-- Run all tSQLt tests on Test Database again to make sure someone didn't forget to Fake a table
set @sql = 'use [<<@test_database_name>>]; exec tSQLt.RunAll; select ''tSQLt.TestResult'' as ''tSQLt.TestResult Failures'', * from tSQLt.TestResult where Result <> ''Success'';'
set @sql = replace(@sql, '<<@test_database_name>>', @test_database_name)
--print @sql

exec sys.sp_executesql @sql

if cast(serverproperty('Edition') as nvarchar(128)) like N'Developer Edition%'
begin
    set @sql = 'use [<<@test_database_name>>]; select @messageOUT = ''tSQLt executed '' + convert(varchar(11), count(*)) + '' tests in '' + convert(varchar(11), datediff(second, min(TestStartTime), max(TestEndTime))) + '' seconds.'' from tSQLt.TestResult;'
    set @sql = replace(@sql, '<<@test_database_name>>', @test_database_name)
    exec sys.sp_executesql @sql, N'@messageOUT varchar(255) output', @messageOUT = @message OUTPUT
    print @message
end
go
