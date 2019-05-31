use master
go

/*

IMPORTANT: Make sure you have the correct Git branch checked out before you run this.
You should really only upgrade your database using the Staging or QA branches. But there's
nothing stopping you from upgrading using the DEV branch or your feature branch.

You can use the @is_repository flag combined with the @branch flag to make sure you don't accidentally bork
your database with an unstable branch. It simply checks the hidden Git files to make sure you have the
correct branch checked out.

If you do mess up your local database just restore it from a backup, check out your desired branch, and run this upgrade.

*/

/* Restore from multiple backup files

use master

restore database [DEV] from
disk = N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup\DEV_01.bak',
disk = N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup\DEV_02.bak',
disk = N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup\DEV_03.bak',
disk = N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup\DEV_04.bak',
disk = N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup\DEV_05.bak',
disk = N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup\DEV_06.bak',
disk = N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup\DEV_07.bak',
disk = N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup\DEV_08.bak',
disk = N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup\DEV_09.bak',
disk = N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup\DEV_10.bak',
disk = N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup\DEV_11.bak',
disk = N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup\DEV_12.bak',
disk = N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup\DEV_13.bak',
disk = N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup\DEV_14.bak',
disk = N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup\DEV_15.bak',
disk = N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup\DEV_16.bak',
disk = N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup\DEV_17.bak',
disk = N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup\DEV_18.bak',
disk = N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup\DEV_19.bak',
disk = N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Backup\DEV_20.bak' with file = 1,
move N'FMCSW' to N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\DATA\DEV.mdf',
move N'FMCSW_log' to N'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\DATA\DEV_log.ldf',
nounload,
replace,
stats = 5

*/

/* Create snapshot

use master

create database [DEV_SS_20180919] on (name = DEV, filename = 'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Data\DEV_SS_20180919.ss') as snapshot of [DEV]

*/

/* Restore snapshot

use master

restore database [DEV] from database_snapshot = 'DEV_SS_20180919'

*/

/* Delete snapshot

use master

drop database [DEV_SS_20180919]

*/


use master
go

restore database [DEV] from database_snapshot = 'DEV_SS_20180919'
go

declare @return int = 0

exec @return = master.dbo.upgrade_database
     @database_name = 'DEV' -- The name of your local database (e.g. Local, DEV)
    ,@folder_path = 'C:\Users\username\Documents\GitHub\repository-name\database' -- Path to your database repository
    ,@debug = 1

select @return as ReVal

go
