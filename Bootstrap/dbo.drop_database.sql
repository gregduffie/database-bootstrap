--====================================================================================================

use master
go

if object_id('dbo.drop_database') is not null
begin
    drop procedure dbo.drop_database
end
go

create procedure dbo.drop_database
(
     @database_name nvarchar(128) -- [Required]
    ,@debug tinyint = 0
)
with encryption
as

set nocount on
set xact_abort on
set transaction isolation level read uncommitted

/* Suggested @debug values
1 = Simple print statements
2 = Simple select statements (e.g. select @variable_1 as variable_1, @variable_2 as variable_2)
3 = Result sets from temp tables (e.g. select '#temp_table_name' as '#temp_table_name' from #temp_table_name where ...)
4 = @sql statements from exec() or sp_executesql
*/

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [drop_database] START'

declare
     @return int = 0
    ,@sql nvarchar(500)

if exists (select 1 from sys.databases where name = @database_name)
begin
    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [drop_database] Setting SINGLE_USER mode on database [' + @database_name + ']'

    set @sql = 'ALTER DATABASE [' + @database_name + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE'

    if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [drop_database] @sql: ' + isnull(@sql, '{null}')

    begin try
        exec @return = sp_executesql @sql
    end try
    begin catch
        print error_message()
        raiserror('Error setting SINGLE_USER mode.', 16, 1)
        return @return
    end catch

    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [drop_database] Dropping database [' + @database_name + ']'

    set @sql = 'DROP DATABASE [' + @database_name + ']'

    if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [drop_database] @sql: ' + isnull(@sql, '{null}')

    begin try
        exec @return = sp_executesql @sql
    end try
    begin catch
        set @sql = 'ALTER DATABASE [' + @database_name + '] SET MULTI_USER'

        exec @return = sp_executesql @sql

        print error_message()
        raiserror('Error dropping database.', 16, 1)
        return @return
    end catch
end

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [drop_database] END'

return @return

go

/* DEV TESTING

create database foo

select * from sys.databases where name = 'foo'

exec master.dbo.drop_database
     @database_name = 'foo'
    ,@debug = 9

select * from sys.databases where name = 'foo'

*/
