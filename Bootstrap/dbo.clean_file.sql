--====================================================================================================

use master
go

if object_id('dbo.clean_file') is not null
begin
    drop procedure dbo.clean_file
end
go

create procedure dbo.clean_file
(
     @module_type char(2) -- U, V, P, TR, FN (all function types), SC (Script) -- https://docs.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-objects-transact-sql?view=sql-server-2017
    ,@file_content nvarchar(max) output
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

/*

Cleans any garbage before and after the object. Specifically for procedures, functions, and triggers.

*/

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [clean_file] START'

declare
     @return int = 0
    ,@cr nchar(1)
    ,@lf nchar(1)
    ,@crlf nchar(2)
    ,@batch_marker nchar(14)
    ,@batch_marker2 nchar(12)
    ,@pos int
    ,@len int

if nullif(@file_content, '') is null
begin
    set @return = -1
    raiserror('@file_content is null.', 16, 1)
    return @return
end

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [clean_file] @module_type: ' + isnull(@module_type, '{null}')

select
     @cr = char(13)
    ,@lf = char(10)
    ,@crlf = @cr + @lf
    ,@batch_marker = '%' + @crlf + '[Gg][Oo]' + @crlf + '%'
    ,@batch_marker2 = '%' + @crlf + '[Gg][Oo]' + '%'

set @len = len(@file_content)

if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [clean_file] @len before replace: ' + isnull(ltrim(str(@len)), '{null}')

-- Normalize procedures. They are the only type that have two difference ways to call it (proc vs procedure).
if @module_type = 'p'
begin
    select
         @file_content = replace(@file_content, 'create proc ', 'create procedure')
        ,@file_content = replace(@file_content, 'alter proc ', 'alter procedure')
end

select
     @file_content = replace(@file_content, char(9), replicate(char(32),4)) -- Change tabs to 4 spaces
    ,@file_content = replace(@file_content, N' go' + @crlf, @crlf + N'go' + @crlf)  -- Remove spaces before the GO (" GO")
    ,@file_content = replace(@file_content, @crlf + N'go ', @crlf + N'go' + @crlf) -- Remove spaces after the GO ("GO ")

-- Are there any carriage returns? There should be at least one.
if patindex('%' + @cr + '%', @file_content) = 0
begin
    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [clean_file] Attempting to fix unexpected EOL markers'

    -- WARNING: I'm assuming that the whole file has this problem. If only one line has the problem then this won't work.
    set @file_content = replace(@file_content, @lf, @crlf) -- Replace LF with CR/LF

    -- Did it work?
    if @debug >= 9
    begin
        set @pos = 1
        while @pos <= 500 -- Only look at the first 500 characters
        begin
            print substring(@file_content, @pos, 1) + ': ' + ltrim(str(ascii(substring(@file_content, @pos, 1))))

            set @pos += 1
        end
    end
end

set @len = len(@file_content)

if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [clean_file] @len after replace: ' + isnull(ltrim(str(@len)), '{null}')

if @module_type <> 'sc' -- SC = Script (Revisions, Post Processing, etc.)
begin
    -- Find the position of the module marker
    select @pos = pos
    from (
        select patindex('%' + m.module_definition + '%', @file_content) as pos
        from (
            select convert(char(2), 'p') as module_type, 'create procedure' as module_definition
            union select 'p', 'alter procedure'
            union select 'fn', 'create function'
            union select 'fn', 'alter function'
            union select 'tr', 'create trigger'
            union select 'tr', 'alter trigger'
            union select 'u', 'create table'
            union select 'u', 'alter table'
            union select 'v', 'create view'
            union select 'v', 'alter view'
        ) m
        where m.module_type = @module_type
    ) p
    where pos > 0

    if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [clean_file] @pos: ' + isnull(ltrim(str(@pos)), '{null}')

    if isnull(@pos, 0) = 0
    begin
        if @debug >= 6 print '[' + convert(varchar(23), getdate(), 121) + '] [clean_file] @file_content (first 100 characters): ' + left(isnull(@file_content, '{null}'), 100)
        if @debug >= 6 print '[' + convert(varchar(23), getdate(), 121) + '] [clean_file] @file_content (last 100 characters): ' + right(isnull(@file_content, '{null}'), 100)

        set @return = -1
        raiserror('There was a problem cleaning this file. Are you sure the @module_type [%s] is correct?', 16, 1, @module_type)
        return @return
    end

    -- Delete everything before the module marker (comments, use statements, set statements)
    set @file_content = substring(@file_content, @pos, @len)

    -- Reset
    select @len = len(@file_content), @pos = null

    -- Find the GO and get rid of everything after it
    select @pos = patindex(@batch_marker, @file_content)

    if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [clean_file] @pos: ' + isnull(ltrim(str(@pos)), '{null}')

    -- If there's no ending GO then don't bother trying to remove the final GO
    if @pos > 0
    begin
        if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [clean_file] Remove the ending GO'

        set @file_content = substring(@file_content, 1, @pos - 1) -- Remove the GO

        if @debug >= 6 print '[' + convert(varchar(23), getdate(), 121) + '] [clean_file] @file_content (first 100 characters): ' + left(isnull(@file_content, '{null}'), 100)
        if @debug >= 6 print '[' + convert(varchar(23), getdate(), 121) + '] [clean_file] @file_content (last 100 characters): ' + right(isnull(@file_content, '{null}'), 100)
    end
    else
    begin
        -- Look for GOs without a carriage return and remove them
        select @pos = patindex(@batch_marker2, @file_content)

        if @pos > 0
        begin
            if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [clean_file] @pos: ' + isnull(ltrim(str(@pos)), '{null}')

            set @file_content = substring(@file_content, 1, @pos - 1) -- Remove the GO

            if @debug >= 6 print '[' + convert(varchar(23), getdate(), 121) + '] [clean_file] @file_content (first 100 characters): ' + left(isnull(@file_content, '{null}'), 100)
            if @debug >= 6 print '[' + convert(varchar(23), getdate(), 121) + '] [clean_file] @file_content (last 100 characters): ' + right(isnull(@file_content, '{null}'), 100)
        end
    end
end

if @debug >= 9 select '@file_content' as '@file_content', @file_content

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [clean_file] END'

return @return

go

/* DEV TESTING

declare
     @module_type char(2)
    ,@file_content nvarchar(max)
    ,@debug tinyint

-- This set statement is commented out because it's double nesting slash star comments.
--set @file_content = N'

--/*
-- comments

--*/

---- stuff and whatnot
--use tempdb
--go

--create procedure dbo.foo
--as

--select 1

---- comment in the code

--/* another comment in the code */

--go

--/*

--foo

--*/

--go

--'

select
     @module_type = 'p'
    ,@debug = 1

exec master.dbo.clean_file
     @module_type = @module_type
    ,@file_content = @file_content output
    ,@debug = @debug

exec sp_executesql @file_content

select * from sys.procedures where name = 'foo'

if object_id('dbo.foo') is not null drop procedure dbo.foo






declare
     @file_path varchar(260)
    ,@module_type char(2)
    ,@file_content nvarchar(max)
    ,@debug tinyint

--set @file_path = 'C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database\database\Post Processing\0100 Rollover SP_Log Table.sql'
set @file_path = 'C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database\database\Revisions\Revisions_2.x.x.sql'

set @debug = 6

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

