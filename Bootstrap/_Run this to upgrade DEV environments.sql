use master
go

declare
     @return int = 0
    ,@sql_params nvarchar(100)
    ,@sql nvarchar(1000)
    ,@failures int
    ,@test_database_name nvarchar(128) = 'tSQLt'
    ,@schedulewise_database_name nvarchar(128) = 'DEV'
    ,@full_path_to_tsqlt_backup nvarchar(128) = 'C:\Program Files\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQL\Backup\tSQLt.bak'
    ,@database_repository_path nvarchar(128) = 'C:\GitHub\database-bootstrap'
    ,@branch varchar(50)

set @branch = case @schedulewise_database_name when 'DEV' then 'dev' when 'QA' then 'qa' when 'STG' then 'staging' else null end

-- Restore Test Database
exec @return = master.dbo.restore_database
     @database_name = @test_database_name
    ,@file_path = @full_path_to_tsqlt_backup
    ,@debug = 1

if @return <> 0 return

-- Upgrade Test Database
exec @return = master.dbo.upgrade_database
     @database_name = @test_database_name
    ,@folder_path = @database_repository_path
    ,@is_repository = 1
    ,@branch = @branch
    ,@debug = 1

if @return <> 0 return

-- Install tSQLt tests on Test Database
exec @return = master.dbo.install_tsqlt_tests
     @database_name = @test_database_name
    ,@folder_path = @database_repository_path
    ,@debug = 1

if @return <> 0 return

-- Run all tSQLt tests on Test Database
set @sql = 'use [<<@test_database_name>>];
exec tSQLt.RunAll'
set @sql = replace(@sql, '<<@test_database_name>>', @test_database_name)
print @sql

exec sys.sp_executesql @sql

-- Check for Test failures
-- select * from tSQLt.tSQLt.TestResult where Result <> 'Success'
set @sql_params = '@failures int = 0 output'
set @sql = 'use [<<@test_database_name>>];
select ''tSQLt.TestResult'' as ''tSQLt.TestResult Failures'', * from tSQLt.TestResult where Result <> ''Success''
set @failures = @@rowcount'
set @sql = replace(@sql, '<<@test_database_name>>', @test_database_name)
print @sql

exec sys.sp_executesql @sql, @sql_params, @failures = @failures output

print '@failures: ' + isnull(ltrim(str(@failures)), '{null}')

if @failures = 0
begin
    -- Upgrade the "Real" Database
    exec @return = master.dbo.upgrade_database
         @database_name = @schedulewise_database_name
        ,@folder_path = @database_repository_path
        ,@is_repository = 1
        ,@branch = @branch
        ,@debug = 1
end

go

/*

-- Upgrade the "Real" Database
exec master.dbo.upgrade_database
     @database_name = 'DEV'
    ,@folder_path = 'C:\GitHub\fmc-schedulewise-database'
    ,@is_repository = 1
    ,@branch = 'dev'
    ,@debug = 1

*/
