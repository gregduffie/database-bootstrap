use master
go

declare
     @return int = 0
    ,@database_name nvarchar(128) = 'msdb'
    ,@folder_path nvarchar(128) = 'C:\GitHub\fmc-schedulewise-database\msdb'

exec @return = master.dbo.upgrade_database
     @database_name = @database_name
    ,@folder_path = @folder_path
    ,@folder_exclusions = 'Build,Bootstrap,Jobs,Roles,Scripts,Tests,Users'
    ,@file_exclusions = null
    ,@allow_system = 1 -- Allows installation on master
    ,@debug = 1

go
