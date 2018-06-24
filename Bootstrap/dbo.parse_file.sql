--====================================================================================================

use master
go

if object_id('dbo.parse_file') is not null
begin
    drop procedure dbo.parse_file
end
go

create procedure dbo.parse_file
(
     @file_content nvarchar(max)
    ,@debug tinyint = 0
)
with encryption
as

/*

This will parse files based on the GOs. This is intended for Revisions, Static Data, and Post Processing scripts. It will return a table with all of the statements in order.

*/

set nocount on
set xact_abort on
--set transaction isolation level read uncommitted -- not necessary.

/* Suggested @debug values
1 = Simple print statements
2 = Simple select statements (e.g. select @variable_1 as variable_1, @variable_2 as variable_2)
3 = Result sets from temp tables (e.g. select '#temp_table_name' as '#temp_table_name' from #temp_table_name where ...)
4 = @sql statements from exec() or sp_executesql
*/

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [parse_file] START'

declare
     @crlf nchar(2)
    ,@batch_marker nchar(14)
    ,@len int
    ,@pos int
    ,@offset int

declare @output table (ident int not null identity(1,1), sql_statement nvarchar(max) not null)

select
     @crlf = char(13) + char(10)
    ,@batch_marker = '%' + @crlf + '[Gg][Oo]' + @crlf + '%'

set @len = len(@file_content)

-- If the file doesn't have a GO at all then add one to the end
if patindex(@batch_marker, @file_content) = 0
begin
    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [parse_file] Adding a batch marker to the end'

    set @file_content += (@crlf + 'go' + @crlf)
    set @len = len(@file_content)
end

set @pos = 1
while @pos < @len
begin
    -- Find the 'GO'
    set @offset = patindex(@batch_marker, substring(@file_content, @pos, @len))

    if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [parse_file] @pos: ' + ltrim(str(@pos)) + ' | @offset: ' + ltrim(str(@offset)) + ' | @len: ' + ltrim(str(@len))

    -- Add 3 characters for the GO and the carriage return.
    set @offset += 3

    insert @output (sql_statement) select substring(@file_content, @pos, @offset - 3) -- Remove the GO by subtracting 3

    set @pos = @pos + @offset + 2
end

select row_number() over (order by ident) as ident, sql_statement from @output where nullif(sql_statement, '') is not null and sql_statement <> @crlf and sql_statement <> @crlf + @crlf

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [parse_file] END'

return 0

go

/* DEV TESTING

declare
     @file_path varchar(260)
    ,@module_type char(2)
    ,@file_content nvarchar(max)
    ,@debug tinyint

--set @file_path = 'C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database\database\Revisions\Revisions_2.x.x.sql'
--set @file_path = 'C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database\database\Post Processing\9999 Remove Obsolete Routines.sql'
set @file_path = 'C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database\database\Post Processing\0100 Rollover SP_Log Table.sql'

set @debug = 6

exec master.dbo.read_file
     @file_path = @file_path
    ,@file_content = @file_content output
    ,@debug = @debug

print @file_path

set @module_type = 'sc'

exec master.dbo.clean_file
     @module_type = @module_type
    ,@file_content = @file_content output
    ,@debug = @debug

--print '----------------------------------------------------------------------------------------------------'
--print @file_content
--print '----------------------------------------------------------------------------------------------------'

exec master.dbo.parse_file
     @file_content = @file_content
    ,@debug = @debug

*/



