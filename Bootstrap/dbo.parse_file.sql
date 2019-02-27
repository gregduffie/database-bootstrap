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

-- If the file is null or just GO, set it to nothing.
if isnull(@file_content, N'') = N'' or @file_content = N'GO' or @file_content = @crlf + N'GO' + @crlf or @file_content = @crlf + N'GO' or @file_content = N'GO' + @crlf
begin
    set @file_content = N''
end
else if patindex(@batch_marker, @file_content) = 0 -- If the file doesn't have a GO at all then add one to the end
begin
    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [parse_file] Adding a batch marker to the end'
    set @file_content += (@crlf + 'go' + @crlf)
end
else if patindex('%' + @crlf + '[Gg][Oo]', @file_content) > 0 -- The file ends with GO but does not have a trailing <CR><LF>
begin
    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [parse_file] Adding a <CR><LF> to the end'
    set @file_content += (@crlf)
end

set @len = len(@file_content)

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
GO

-- Test GO at EOF.
declare @file_content nvarchar(max), @CRLF nchar(2) = char(13) + char(10)

-- No GO at all.
set @file_content = N'test no ender'
exec master.dbo.parse_file
     @file_content = @file_content
    ,@debug = 1

-- No GO at the end.
set @file_content = N'test no ender' + @CRLF + N'GO' + @CRLF + N'more stuff'
exec master.dbo.parse_file
     @file_content = @file_content
    ,@debug = 1

-- GO at the end followed by nothing
set @file_content = N'test no ender' + @CRLF + N'GO'
exec master.dbo.parse_file
     @file_content = @file_content
    ,@debug = 1

-- GO at the end followed by <CR><LF>
set @file_content = N'start with something go in the midst of it' + @CRLF + N'GO' + @CRLF
exec master.dbo.parse_file
     @file_content = @file_content
    ,@debug = 1

-- GO in middle and at the end followed by <CR><LF>
set @file_content = N'happy path test go right here' + @CRLF + N'GO' + @CRLF + N'more text at the end go in the middle' + @CRLF + N'GO' + @CRLF
exec master.dbo.parse_file
     @file_content = @file_content
    ,@debug = 1

-- GO in middle and at the end followed by <CR><LF>
set @file_content = N'happy path test go right here' + @CRLF + N'GO' + @CRLF + N' some text in between ' + @CRLF + N'GO' + @CRLF + N'more text at the end go in the middle' + @CRLF + N'GO' + @CRLF
exec master.dbo.parse_file
     @file_content = @file_content
    ,@debug = 1

-- <CR><LF> GO <CR><LF>
set @file_content = @CRLF + N'GO' + @CRLF
exec master.dbo.parse_file
     @file_content = @file_content
    ,@debug = 1

-- GO <CR><LF>
set @file_content = N'GO' + @CRLF
exec master.dbo.parse_file
     @file_content = @file_content
    ,@debug = 1

-- <CR><LF> GO
set @file_content = @CRLF + N'GO'
exec master.dbo.parse_file
     @file_content = @file_content
    ,@debug = 1

-- Just GO
set @file_content = N'GO'
exec master.dbo.parse_file
     @file_content = @file_content
    ,@debug = 1

-- NULL file content
set @file_content = null
exec master.dbo.parse_file
     @file_content = @file_content
    ,@debug = 1
*/
