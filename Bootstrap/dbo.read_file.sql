--====================================================================================================

use master
go

if object_id('dbo.read_file') is not null
begin
    drop procedure dbo.read_file
end
go

create procedure dbo.read_file
(
     @file_path varchar(260)                    -- [Required] Path to file (i.e., C:\Users\username\Documents\GitHub\repository-name\database\Stored Procedures\dbo.GetUsers.sql)
    ,@file_content nvarchar(max) = null output  -- [Optional] No need to pass anything.
    ,@debug tinyint = 0
)
with encryption
as

/*

Reads an individual file from disk and sends the file content back via an output parameter.

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

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [read_file] START'

declare
     @return int = 0
    ,@bulkcolumn varbinary(max)
    ,@sql nvarchar(500)
    ,@sql_params nvarchar(100)

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [read_file] @file_path: ' + isnull(@file_path, '{null}')

if @file_path not like '%.git\HEAD' -- Bypass if you're checking for the .git HEAD file
begin
    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [read_file] Running validate_path'

    exec @return = master.dbo.validate_path
         @path = @file_path
        ,@is_file = 1
        ,@is_directory = 0
        ,@debug = @debug

    if @return <> 0 return @return
end

set @sql = N'select @bulkcolumn = bulkcolumn from openrowset(bulk ''<<@file_path>>'', codepage = ''raw'', single_blob) o'
set @sql = replace(@sql, '<<@file_path>>', @file_path)
set @sql_params = N'@bulkcolumn varbinary(max) output'

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [read_file] @sql: ' + isnull(@sql, '{null}')

exec sp_executesql @sql, @sql_params, @bulkcolumn = @bulkcolumn output

if @return <> 0
begin
    raiserror('There was a problem reading [%s]', 16, 1, @file_path)
    return @return
end

set @file_content = case ascii(substring(@bulkcolumn, 4, 1)) when 0 then cast(@bulkcolumn as nvarchar(max)) else cast(@bulkcolumn as varchar(max)) end

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [read_file] END'

return @return

go

/* DEV TESTING

declare
     @file_path varchar(260)
    ,@module_type char(2)
    ,@file_content nvarchar(max)
    ,@debug tinyint

select
     @file_path = 'C:\Users\username\Documents\GitHub\repository-name\database\Revisions\Revisions_2.x.x.sql'
    ,@debug = 4

exec master.dbo.read_file
     @file_path = @file_path
    ,@file_content = @file_content output
    ,@debug = @debug

print @file_path
print @file_content

set @module_type = 'sc'

exec master.dbo.clean_file
     @module_type = @module_type
    ,@file_content = @file_content output
    ,@debug = @debug

*/

