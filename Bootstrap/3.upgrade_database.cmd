sqlcmd -S "(local)\SQL2017" -d "master" -E -I -Q "exec master.dbo.upgrade_database @database_name = N'tSQLt', @folder_path = N'C:\Users\gduffie\Documents\GitHub\database-bootstrap', @debug = 1"
pause