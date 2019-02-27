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

/* Create snapshot

use master

create database [DEV_SS_20180919] on (name = DEV, filename = 'C:\Program Files\Microsoft SQL Server\MSSQL14.SQL2017\MSSQL\Data\DEV_SS_20180919.ss') as snapshot of [DEV]

*/

/* Restore snapshot

use master

restore database [ScheduleWise] from database_snapshot = 'DEV_SS_20180919'

*/

/* Delete snapshot

use master

drop database [DEV_SS_20180919]

*/


use master
go

restore database [ScheduleWise] from database_snapshot = 'DEV_SS_20180919'
go

declare @return int = 0

exec @return = master.dbo.upgrade_database
     @database_name = 'ScheduleWise' -- The name of your local database (e.g. Local, DEV)
    ,@folder_path = 'C:\Users\gduffie\Documents\GitHub\database-bootstrap' -- Path to your database repository
    ,@is_repository = 1
    ,@branch = 'dev'
    ,@debug = 1

select @return as ReVal

go
