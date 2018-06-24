--====================================================================================================

use master
go

if object_id('dbo.create_database') is not null
begin
    drop procedure dbo.create_database
end
go

create procedure dbo.create_database
(
     @path varchar(260) -- Path to repository folder (i.e., C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database\) or the whatever you want to install folder (i.e., C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database\database\Bootstrap)
    ,@database_name nvarchar(128)
    ,@debug tinyint = 0
)
with encryption
as

/*

This will look at the repository location and create a new, clean database

*/

set nocount on
--set xact_abort on -- disabled on purpose.
--set transaction isolation level read uncommitted -- not necessary.

/* Suggested @debug values
1 = Simple print statements
2 = Simple select statements (e.g. select @variable_1 as variable_1, @variable_2 as variable_2)
3 = Result sets from temp tables (e.g. select '#temp_table_name' as '#temp_table_name' from #temp_table_name where ...)
4 = @sql statements from exec() or sp_executesql
*/

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [create_database] START'

select 'Do some stuff here'

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [create_database] END'

go

