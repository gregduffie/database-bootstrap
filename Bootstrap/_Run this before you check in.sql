use master
go

declare
     @return int = 0
    ,@sql nvarchar(1000)
    ,@test_database_name nvarchar(128) = 'tSQLt'
    ,@full_path_to_tsqlt_backup nvarchar(128) = 'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup\tSQLt.bak'
    ,@folder_path nvarchar(128) = 'C:\Users\gduffie\Documents\GitHub\database-bootstrap'
    ,@test_folder_path nvarchar(128)

set @test_folder_path = @folder_path + '\Tests'

-- Restore Test Database
exec @return = master.dbo.restore_database
     @database_name = @test_database_name
    ,@file_path = @full_path_to_tsqlt_backup
    ,@debug = 1

if @return <> 0 return

-- Upgrade Test Database
exec @return = master.dbo.upgrade_database
     @database_name = @test_database_name
    ,@folder_path = @folder_path
    ,@folder_exclusions = 'Build,Bootstrap,Jobs,Roles,Scripts,Tests,Users'
    ,@file_exclusions = 'dbo.JSONHierarchy.sql,dbo.udf_ToJSON.sql'
    ,@debug = 1

if @return <> 0 return

-- Install tSQLt tests on Test Database
exec @return = master.dbo.install_tsqlt_tests
     @database_name = @test_database_name
    ,@folder_path = @test_folder_path
    ,@debug = 1

if @return <> 0 return

-- Run all tSQLt tests on Test Database
set @sql = 'use [<<@test_database_name>>]; exec tSQLt.RunAll; select ''tSQLt.TestResult'' as ''tSQLt.TestResult Failures'', * from tSQLt.TestResult where Result <> ''Success'';'
set @sql = replace(@sql, '<<@test_database_name>>', @test_database_name)
--print @sql

exec sys.sp_executesql @sql

go
