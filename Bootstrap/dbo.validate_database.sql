--====================================================================================================

use master
go

if object_id('dbo.validate_database') is not null
begin
    drop procedure dbo.validate_database
end
go

create procedure dbo.validate_database
(
     @database_name varchar(128)    -- TODO: Handle database name with/without brackets
    ,@allow_system bit = 0          -- Allows installation on master for things like Ola H.'s tools, Brent Ozar's Blitz tools, etc.
    ,@debug tinyint = 0
)
with encryption
as

set nocount on
--set xact_abort on -- disabled on purpose.
--set transaction isolation level read uncommitted -- not necessary.

/* Suggested @debug values
1 = Simple print statements
2 = Simple select statements (e.g. select @variable_1 as variable_1, @variable_2 as variable_2)
3 = Result sets from temp tables (e.g. select '#temp_table_name' as '#temp_table_name' from #temp_table_name where ...)
4 = @sql statements from exec() or sp_executesql
*/

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [validate_database] START'

declare @return int = 0

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [validate_database] Checking @database_name: ' + isnull(@database_name, '{null}')

-- Validate database
if nullif(@database_name, '') is null
begin
    set @return = -1
    raiserror('@database_name can not be empty.', 16, 1)
    return @return
end

-- Fail if you try to install on a system database
if exists (select 1 from sys.databases where name = @database_name and database_id <= 4) and @allow_system = 0
begin
    set @return = -1
    raiserror('You can not install on [%s].', 16, 1, @database_name)
    return @return
end

-- Make sure the database is online and ready
if not exists (select 1 from sys.databases where is_read_only = 0 and is_in_standby = 0 and [state] = 0 and [name] = @database_name)
begin
    set @return = -1
    raiserror('[%s] does not exist or is not online.', 16, 1, @database_name)
    return @return
end

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [validate_database] END'

return @return

go

/* DEV TESTING

declare @return int

exec @return = master.dbo.validate_database
     @database_name = 'master'
    ,@allow_system = 0
    ,@debug = 1

select @return

exec @return = master.dbo.validate_database
     @database_name = 'master'
    ,@allow_system = 1
    ,@debug = 1

select @return

*/

