--====================================================================================================

use master
go

create or alter procedure dbo.read_file
(
     @file_path nvarchar(260)                   -- [Required] Path to file (i.e., C:\Users\username\Documents\GitHub\repository-name\database\Stored Procedures\dbo.GetUsers.sql)
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
    --,@bulkcolumn varbinary(max)
    ,@bulkcolumn nvarchar(max)
    ,@sql nvarchar(500)
    ,@sql_params nvarchar(100)

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [read_file] @file_path: ' + isnull(@file_path, '{null}')

if @file_path not like N'%.git\HEAD' -- Bypass if you're checking for the .git HEAD file
begin
    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [read_file] Running validate_path'

    exec @return = master.dbo.validate_path
         @path = @file_path
        ,@is_file = 1
        ,@is_directory = 0
        ,@debug = @debug

    if @return <> 0 return @return
end

--set @sql = N'select @bulkcolumn = bulkcolumn from openrowset(bulk N''<<@file_path>>'', single_blob, codepage = N''raw'') o' -- Reads the file as binary
set @sql = N'select @bulkcolumn = convert(nvarchar(max), wholeline) from openrowset(bulk N''C:\GitHub\database-bootstrap\Bootstrap\UnicodeTesting.sql'', formatfile = N''C:\GitHub\database-bootstrap\Bootstrap\UnicodeTesting.fmt'', codepage = N''65001'') o'
--set @sql = N'select @bulkcolumn = bulkcolumn from openrowset(bulk N''C:\GitHub\database-bootstrap\Bootstrap\UnicodeTesting.sql'', single_blob, codepage = ''65001'') o'

declare @wtf nvarchar(max)
select @wtf = convert(nvarchar(max), wholeline) from openrowset(bulk N'C:\GitHub\database-bootstrap\Bootstrap\UnicodeTesting.sql', formatfile = N'C:\GitHub\database-bootstrap\Bootstrap\UnicodeTesting.fmt') o
print N'@wtf:' + @wtf

set @sql = replace(@sql, N'<<@file_path>>', @file_path)
--set @sql_params = N'@bulkcolumn varbinary(max) output'
set @sql_params = N'@bulkcolumn nvarchar(max) output'

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [read_file] @sql: ' + isnull(@sql, '{null}')

exec @return = sp_executesql @sql, @sql_params, @bulkcolumn = @bulkcolumn output

--if @return <> 0
--begin
--    raiserror(N'There was a problem reading [%s]', 16, 1, @file_path)
--    return @return
--end

print 'substring:'
--print substring(@bulkcolumn, 0, 1)
print substring(@bulkcolumn, 1, 1)
print substring(@bulkcolumn, 2, 1)
print substring(@bulkcolumn, 3, 1)
print substring(@bulkcolumn, 4, 1)
print substring(@bulkcolumn, 5, 1)
print substring(@bulkcolumn, 6, 1)
print substring(@bulkcolumn, 7, 1)

print 'ascii(substring:'
--print ascii(substring(@bulkcolumn, 0, 1))
print ascii(substring(@bulkcolumn, 1, 1))
print ascii(substring(@bulkcolumn, 2, 1))
print ascii(substring(@bulkcolumn, 3, 1))
print ascii(substring(@bulkcolumn, 4, 1))
print ascii(substring(@bulkcolumn, 5, 1))
print ascii(substring(@bulkcolumn, 6, 1))
print ascii(substring(@bulkcolumn, 7, 1))

print 'char(ascii(substring:'
--print char(ascii(substring(@bulkcolumn, 0, 1)))
print char(ascii(substring(@bulkcolumn, 1, 1)))
print char(ascii(substring(@bulkcolumn, 2, 1)))
print char(ascii(substring(@bulkcolumn, 3, 1)))
print char(ascii(substring(@bulkcolumn, 4, 1)))
print char(ascii(substring(@bulkcolumn, 5, 1)))
print char(ascii(substring(@bulkcolumn, 6, 1)))
print char(ascii(substring(@bulkcolumn, 7, 1)))



--set @file_content = case ascii(substring(@bulkcolumn, 4, 1)) when 0 then cast(@bulkcolumn as nvarchar(max)) else cast(@bulkcolumn as nvarchar(max)) end
--set @file_content = convert(nvarchar(max), @bulkcolumn)
set @file_content = convert(nvarchar(max), @bulkcolumn)

print '@file_content: '
print @file_content

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
     @file_path = 'C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database\fmcsw\Revisions\Revisions_2.x.x.sql'
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


















declare
     @file_path nvarchar(260)
    ,@module_type nchar(2)
    ,@file_content nvarchar(max)
    ,@debug tinyint

set @file_path = N'C:\GitHub\database-bootstrap\Bootstrap\UnicodeTesting.sql'
--set @file_path = N'C:\GitHub\database-bootstrap\Bootstrap\NonUnicodeTesting.sql'

set @debug = 9

exec master.dbo.read_file
     @file_path = @file_path
    ,@file_content = @file_content output
    ,@debug = @debug

--print @file_path
print '-before clean---------------------------------------------------------------------------------------------------'
print @file_content
print '----------------------------------------------------------------------------------------------------'

--set @module_type = 'sc'

--exec master.dbo.clean_file
--     @module_type = @module_type
--    ,@file_content = @file_content output
--    ,@debug = @debug

--print '----------------------------------------------------------------------------------------------------'
--print @file_content
--print '----------------------------------------------------------------------------------------------------'

--exec master.dbo.parse_file
--     @file_content = @file_content
--    ,@debug = @debug
--GO






