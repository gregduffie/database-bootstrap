--====================================================================================================

use master
go

-- To allow advanced options to be changed.
exec sp_configure 'show advanced options', 1
go

-- To update the currently configured value for advanced options.
reconfigure
go

-- To enable the feature.
exec sp_configure 'xp_cmdshell', 1
go

-- To update the currently configured value for this feature.
reconfigure
go

--====================================================================================================

use master
go

exec sp_configure 'clr enabled', 1
go

reconfigure
go

if convert(int, serverproperty('ProductMajorVersion')) >= 14
begin
    exec sp_configure 'clr strict security', 0

    reconfigure
end
go

--====================================================================================================

use master
go

if object_id('dbo.udf_split_8k_string_single_delimiter') is not null
begin
    drop function dbo.udf_split_8k_string_single_delimiter
end
go

create function dbo.udf_split_8k_string_single_delimiter
(
     @string varchar(8000)
    ,@delimiter char(1) = ','
)
--WARNING!!! DO NOT USE MAX DATA-TYPES HERE! IT WILL KILL PERFORMANCE!
--This method produces zero reads compared to rs_fn_splitNVARCHAR
returns table with schemabinding as
return

/*
Taken from Jeff Moden's article:
http://www.sqlservercentral.com/articles/Tally+Table/72993/
*/

with e1(n) as
( -- 10E+1 or 10 rows
    select 1 union all select 1 union all select 1 union all
    select 1 union all select 1 union all select 1 union all
    select 1 union all select 1 union all select 1 union all select 1
)
,e2(n) as
( -- 10E+2 or 100 rows
    select 1 from e1 a, e1 b
)
,e4(n) as
( -- 10E+4 or 10,000 rows max
    select 1 from e2 a, e2 b
)
,cteTally(n) as
( -- This provides the base CTE and limits the number of rows right up front for both a performance gain and prevention of accidental overruns
    select top (isnull(datalength(@string),0)) row_number() over (order by (select null)) from e4
),
cteStart(n1) as
( -- This returns N+1 (starting position of each element just once for each delimiter)
    select 1 union all
    select t.n + 1 from cteTally t where substring(@string, t.n, 1) = @delimiter
),
cteLen(n1, l1) as
( -- Return start and length (for use in substring)
    select s.n1, isnull(nullif(charindex(@delimiter, @string, s.n1), 0) - s.n1, 8000)
    from cteStart s
)
-- Do the actual split. The ISNULLNULLIF combo handles the length for the final element when no delimiter is found.
select
     ItemNumber = row_number() over(order by l.n1)
    ,Item = substring(@string, l.n1, l.l1)
from cteLen l;

go

/*

declare
     @string varchar(8000) = 'D:\temp\temp_1.sql,D:\temp\temp_2.sql,D:\temp\temp_3.sql'
    ,@delimiter char(1) = ','

select * from dbo.udf_split_8k_string_single_delimiter(@string, @delimiter)

*/

--====================================================================================================

use master
go

if exists (select 1 from information_schema.routines where routine_name = 'directory_slash' and routine_schema = 'dbo')
begin
    drop function dbo.directory_slash
end
go

create function dbo.directory_slash
(
     @beginning_slash varchar(3)
    ,@directory varchar(260)
    ,@ending_slash varchar(3)
)
returns varchar(260)
with encryption
as
begin
    select
         @beginning_slash = isnull(@beginning_slash, '')
        ,@directory = isnull(@directory, '')
        ,@ending_slash = isnull(@ending_slash, '')

    --remove all slashes from beginning
    while left(@directory, 1) in ('\', '/')
    begin
        set @directory = right(@directory, len(@directory) - 1)
    end

    --remove all slashes from end
    while right(@directory, 1) in ('\', '/')
    begin
        set @directory = left(@directory, len(@directory) - 1)
    end

    --add slashes
    return @beginning_slash + @directory + @ending_slash
end

go

/* DEV TESTING

Returns a folder with the slash format that you want. It first removes all slashes from the beginning and end and then adds back the slash format you specify.

Syntax:
    dbo.directory_slash(@beginning_slash, @directory, @ending_slash)

Arguments:
    @beginning_slash - varchar(3)
        Any non-unicode string
    @directory - varchar(260)
        The folder or directory that you want to re-format.
    @ending_slash - varchar(3)
        Any non-unicode string

Returns:
    varchar(260)

Examples:
    set nocount on

    --Remove the beginning slash
    select master.dbo.directory_slash(null, '\folder_name_a\folder_name_b\', '\')

    --Remove the ending slash
    select master.dbo.directory_slash('\', '\folder_name_a\folder_name_b\', null)

    --Remove both
    select master.dbo.directory_slash(null, '\folder_name_a\folder_name_b\', null)

    --Add both #1 (ensures that they are there when you aren't sure of the input)
    select master.dbo.directory_slash('\', '\folder_name_a\folder_name_b\', '\')

    --Add both #2 (ensures that they are there when you aren't sure of the input)
    select master.dbo.directory_slash('\', 'folder_name_a\folder_name_b', '\')

    --Add multiple slashes
    select master.dbo.directory_slash('\\', 'folder_name_a\folder_name_b', '\\\')

    --Remove multiple slashes
    select master.dbo.directory_slash('\', '\\\folder_name_a\folder_name_b\\', '\')

    set nocount off

*/

--====================================================================================================

use master
go

if exists (select 1 from information_schema.routines where routine_name = 'get_file_name_from_file_path' and routine_schema = 'dbo')
begin
    drop function dbo.get_file_name_from_file_path
end
go

create function dbo.get_file_name_from_file_path
(
     @file_path nvarchar(260)
)
returns varchar(260)
as
begin
    return right(@file_path, isnull(nullif(charindex('\', reverse(@file_path)), 0), 1) - 1) -- TODO: I don't like the isnull/nullif...good enough for now.
end
go

/* DEV TESTING

select master.dbo.get_file_name_from_file_path('c:\temp\foo.sql')
select master.dbo.get_file_name_from_file_path('foo.sql')
*/

--====================================================================================================

use master
go

if exists (select 1 from information_schema.routines where routine_name = 'get_file_extension_from_file_name' and routine_schema = 'dbo')
begin
    drop function dbo.get_file_extension_from_file_name
end
go

create function dbo.get_file_extension_from_file_name
(
     @file_name nvarchar(260)
)
returns varchar(260)
as
begin
    return right(@file_name, isnull(nullif(charindex('.', reverse(@file_name)), 0), 1) - 1) -- TODO: I don't like the isnull/nullif...good enough for now.
end
go

/* DEV TESTING

select dbo.get_file_extension_from_file_name('foo.sql')
select dbo.get_file_extension_from_file_name('foosql')

*/

--====================================================================================================

use master
go

if object_id('dbo.validate_path') is not null
begin
    drop procedure dbo.validate_path
end
go

create procedure dbo.validate_path
(
     @path varchar(260)                     -- [Required] A folder/directory or full file path including the file name and extension.
    ,@is_file bit = null output             -- [Optional] Returns 1 if @path points to a file. If you pass a value into @is_file then it will throw an error if the @path is not what you expect.
    ,@is_directory bit = null output        -- [Optional] Returns 1 if @path points to a directory. If you pass a value into @is_directory then it will throw an error if the @path is not what you expect.
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

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [validate_path] START'

/*

Alternative method: exec sys.xp_dirtree 'c:\temp\',1,1

Params:
    directory - This is the directory you pass when you call the stored procedure; for example 'D:\Backup'.
    depth  - This tells the stored procedure how many subfolder levels to display.  The default of 0 will display all subfolders.
    isfile - This will either display files as well as each folder.  The default of 0 will not display any files and it will only return two columns instead of three.

-- Output
declare @devnull table (id int null identity(1,1), subdirectory nvarchar(512) null, depth int null, isfile bit null)

-- Output when @isfile = 0
declare @devnull table (id int null identity(1,1), subdirectory nvarchar(512) null, depth int null)

Additional methods:
    exec sys.xp_cmdshell 'dir "c:\temp\empty"'
    exec sys.xp_subdirs 'c:\temp'

*/

declare
     @return int = 0
    ,@file_exists bit
    ,@directory_exists bit

declare @output table (file_exists bit not null default (0), directory_exists bit not null default (0), parent_directory_exists bit not null default (0))

if nullif(@path, '') is null
begin
    select @return = -1, @is_file = 0, @is_directory = 0
    raiserror('@path can not be empty', 16, 1)
    return @return
end

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [validate_path] Running xp_fileexists on ' + @path

if @debug >= 6 exec sys.xp_fileexist @path

insert @output (file_exists, directory_exists, parent_directory_exists)
    exec sys.xp_fileexist @path

select
     @file_exists = file_exists
    ,@directory_exists = directory_exists
from
    @output

if @debug >= 4 select '@output' as [output], * from @output

if @is_file = 1 and @file_exists = 0 set @return = -1 -- I expected @path to contain a file but it doesn't.
if @is_file = 0 and @file_exists = 1 set @return = -1 -- I expected @path to contain a directory but it doesn't.
if @is_directory = 1 and @directory_exists = 0 set @return = -1 -- I expected @path to contain a directory but it doesn't.
if @is_directory = 0 and @directory_exists = 1 set @return = -1 -- I expected @path to contain a file but it doesn't.

-- Set the output values
select @is_file = @file_exists, @is_directory = @directory_exists

if @is_file = 0 and @is_directory = 0 set @return = -1 -- File or folder does not exist.

--if @return <> 0 raiserror('Invalid path.', 16, 1) -- Don't raise an error.

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [validate_path] END'

return @return

go

/* DEV TESTING

declare
     @return int
    ,@is_file bit
    ,@is_directory bit
    ,@expected_return int
    ,@expected_is_file bit
    ,@expected_is_directory bit
    ,@path varchar(260)
    ,@file varchar(260) = 'c:\temp\test.txt'
    ,@directory varchar(260) = 'c:\temp'
    ,@ident smallint

declare @combos table (ident int not null identity(1,1), is_file bit null, is_directory bit null, [path] varchar(260) null, expected_return int null, expected_is_file bit null, expected_is_directory bit null)

-- File path
insert @combos (is_file, is_directory, [path], expected_return, expected_is_file, expected_is_directory) values
     (null, null, @file, 0, 1, 0)
    ,(null, 0, @file, 0, 1, 0)
    ,(0, null, @file, -1, 1, 0)
    ,(0, 0, @file, -1, 1, 0)
    ,(0, 1, @file, -1, 1, 0)
    ,(1, 1, @file, -1, 1, 0)
    ,(1, 0, @file, 0, 1, 0) -- 7

-- Directory
insert @combos (is_file, is_directory, [path], expected_return, expected_is_file, expected_is_directory) values
     (null, null, @directory, 0, 0, 1)
    ,(null, 0, @directory, -1, 0, 1)
    ,(0, null, @directory, 0, 0, 1)
    ,(0, 0, @directory, -1, 0, 1)
    ,(0, 1, @directory, 0, 0, 1)
    ,(1, 1, @directory, -1, 0, 1)
    ,(1, 0, @directory, -1, 0, 1) -- 14

-- Files that don't exist
insert @combos (is_file, is_directory, [path], expected_return, expected_is_file, expected_is_directory) values
     (null, null, 'c:\gibberish.txt', -1, 0, 0)
    ,(null, 0, 'c:\gibberish.txt', -1, 0, 0)
    ,(0, null, 'c:\gibberish.txt', -1, 0, 0)
    ,(0, 0, 'c:\gibberish.txt', -1, 0, 0)
    ,(0, 1, 'c:\gibberish.txt', -1, 0, 0)
    ,(1, 1, 'c:\gibberish.txt', -1, 0, 0)
    ,(1, 0, 'c:\gibberish.txt', -1, 0, 0) -- 21

-- Directories that don't exist
insert @combos (is_file, is_directory, [path], expected_return, expected_is_file, expected_is_directory) values
     (null, null, 'c:\gibberish', -1, 0, 0)
    ,(null, 0, 'c:\gibberish', -1, 0, 0)
    ,(0, null, 'c:\gibberish', -1, 0, 0)
    ,(0, 0, 'c:\gibberish', -1, 0, 0)
    ,(0, 1, 'c:\gibberish', -1, 0, 0)
    ,(1, 1, 'c:\gibberish', -1, 0, 0)
    ,(1, 0, 'c:\gibberish', -1, 0, 0) -- 28

-- Nulls
insert @combos (is_file, is_directory, [path], expected_return, expected_is_file, expected_is_directory) values
     (null, null, null, -1, 0, 0)
    ,(null, 0, null, -1, 0, 0)
    ,(0, null, null, -1, 0, 0)
    ,(0, 0, null, -1, 0, 0)
    ,(0, 1, null, -1, 0, 0)
    ,(1, 1, null, -1, 0, 0)
    ,(1, 0, null, -1, 0, 0) -- 35

select * from @combos

-- This will loop over every combination and validate it.
while exists (select 1 from @combos)
begin
    select top (1)
         @ident = ident
        ,@is_file = is_file
        ,@is_directory = is_directory
        ,@path = [path]
        ,@expected_return = expected_return
        ,@expected_is_file = expected_is_file
        ,@expected_is_directory = expected_is_directory
    from
        @combos
    order by
        ident

    print '@is_file (before): ' + isnull(ltrim(str(@is_file)), '{null}')
    print '@is_directory (before): ' + isnull(ltrim(str(@is_directory)), '{null}')

    exec @return = master.dbo.validate_path
         @path = @path
        ,@is_file = @is_file output
        ,@is_directory = @is_directory output
        ,@debug = 1

    print '@ident: ' + ltrim(str(@ident))
    print '@return: ' + ltrim(str(@return))
    print '@is_file: ' + isnull(ltrim(str(@is_file)), '{null}')
    print '@is_directory: ' + isnull(ltrim(str(@is_directory)), '{null}')
    print '@expected_return: ' + ltrim(str(@expected_return))
    print '@expected_is_file: ' + ltrim(str(@expected_is_file))
    print '@expected_is_directory: ' + ltrim(str(@expected_is_directory))

    if @return <> @expected_return
    or @is_file <> @expected_is_file
    or @is_directory <> @expected_is_directory
    begin
        select ident, @return as actual_return, expected_return, @is_file as actual_is_file, expected_is_file, @is_directory as actual_is_directory, expected_is_directory, [path] from @combos where ident = @ident
        --raiserror('Failed on @ident %i', 16, 1, @ident)
        break
    end

    delete @combos where ident = @ident
end

*/

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

--====================================================================================================

use master
go

if object_id('dbo.validate_repository') is not null
begin
    drop procedure dbo.validate_repository
end
go

create procedure dbo.validate_repository
(
     @repository_path nvarchar(2000)    -- [Required] The full path to the base of the repository (e.g., C:\Users\username\Documents\GitHub\repository-name) where the (hidden) .git folder is located.
    ,@branch varchar(50) = null         -- [Optional] The branch that you are expecting to be checked out (i.e., "ref: refs/heads/development").
    ,@debug tinyint = 0
)
with encryption
as

/*

This will validate that your repository exists and you have the correct branch checked out.

*/

set nocount on
--set xact_abort on -- disabled on purpose.
--set transaction isolation level read uncommitted -- not necessary.

/* Suggested @debug values
1 = Simple print statements
2 = Simple select statements (e.g. select @variable_1 as variable_1, @variable_2 as variable_2)
3 = Result sets from temp tables (e.g. select '#temp_table_name' as '#temp_table_name', * from #temp_table_name where ...)
4 = @sql statements from exec() or sp_executesql
*/

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [validate_repository] START'

declare
     @return int = 0
    ,@file_path varchar(260)
    ,@file_content nvarchar(max)
    ,@head varchar(200)

-- Add a slash to the end if needed
set @repository_path = master.dbo.directory_slash(null, @repository_path, '\')

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [validate_repository] Running validate_path to check for the "' + @repository_path + '" folder'

-- Make sure the .git folder exists at the repository path
exec @return = master.dbo.validate_path
     @path = @repository_path
    ,@is_file = 0
    ,@is_directory = 1
    ,@debug = @debug

if @return <> 0
begin
    raiserror('Invalid path.', 16, 1)
    return @return
end

set @file_path = @repository_path + '.git\HEAD'

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [validate_repository] Running read_file on "' + @file_path + '"'

-- ref: refs/heads/development
exec @return = master.dbo.read_file
     @file_path = @file_path
    ,@file_content = @file_content output
    ,@debug = 1

if @return <> 0 return @return -- The previous call will throw an error so don't bother throwing another.

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [validate_repository] @file_content: ' + @file_content

if nullif(@branch, '') is not null
begin
    set @head = 'ref: refs/heads/' + @branch

    if charindex(@head, @file_content) = 0
    begin
        set @return = -1
        raiserror('[%s] does not contain the [%s] branch in the HEAD file.', 16, 1, @file_path, @branch)
        return @return
    end
end

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [validate_repository] END'

return @return

go

/* DEV TESTING

declare
     @return int = 0
    ,@repository_path nvarchar(2000)
    ,@branch varchar(50)

set @repository_path = 'C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database'
set @branch = 'develop'

exec @return = master.dbo.validate_repository
     @repository_path = @repository_path
    ,@branch = @branch
    ,@debug = 1

select @return as [return]

*/

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

--====================================================================================================

use master
go

if object_id('dbo.list_files') is not null
begin
    drop procedure dbo.list_files
end
go

create procedure dbo.list_files
(
     @folder_path varchar(260)      -- [Required] Path to folder (i.e., C:\Users\username\Documents\GitHub\repository-name\)
    ,@include_subfolders bit = 0    -- [Optional] Defaults to exclude subfolders
    ,@extension varchar(10) = 'sql' -- [Required] No period or slash necessary
    ,@debug tinyint = 0
)
with encryption
as

/*

This procedure will list all of the files in a directory. If you turn the @include_subfolders flag on it will include sub-folders/directories too.

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

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [list_files] START'

declare
     @xp_cmdshell nvarchar(500)
    ,@full_extension varchar(12)

-- Make sure there's a backslash on the end of the @folder_path
set @folder_path = master.dbo.directory_slash(null, @folder_path, '\')

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [list_files] @folder_path: ' + isnull(@folder_path, '{null}')

if nullif(@extension, '') is null
begin
    set @full_extension = '*.*'
end
else
begin
    set @full_extension = '*.' + replace(@extension, '.', '') -- TODO: Removes all periods. Need to change it to only remove the leading period.
end

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [list_files] @full_extension: ' + isnull(@full_extension, '{null}')

if @include_subfolders = 1
begin
    -- Get all of the files at this directory and sub-directories in bare mode
    set @xp_cmdshell = N'dir /b /s "' + @folder_path + @full_extension + N'"'
end
else
begin
    -- Get all of the files at this directory in bare mode
    set @xp_cmdshell = N'dir /b "' + @folder_path + @full_extension + N'"'
end

if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [list_files] @xp_cmdshell: ' + isnull(@xp_cmdshell, '{null}')

exec xp_cmdshell @xp_cmdshell

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [list_files] END'

return 0

go

/* DEV TESTING

exec master.dbo.list_files
     @folder_path = 'C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database\'
    ,@include_subfolders = 1
    ,@extension = 'sql'
    ,@debug = 2

-- Not sure when this would ever happen...
exec master.dbo.list_files
     @folder_path = 'C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database\fmcsw\revisions\Revisions_2.x.x.sql'
    ,@include_subfolders = 1
    ,@extension = 'sql'
    ,@debug = 2

*/

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

-- Treat table files as scripts because if the table is missing it will get recreated from scratch instead of having to go through all of the Revisions script changes.
if @module_type = 'u' set @module_type = 'sc'

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [clean_file] @module_type: ' + isnull(@module_type, '{null}')

select
     @cr = char(13)
    ,@lf = char(10)
    ,@crlf = @cr + @lf
    ,@batch_marker = '%' + @crlf + '[Gg][Oo]' + @crlf + '%'
    ,@batch_marker2 = '%' + @crlf + '[Gg][Oo]' + '%'

set @len = len(@file_content)

if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [clean_file] @len before replace: ' + isnull(ltrim(str(@len)), '{null}')

-- Normalize procedures because they are the only type that have two different ways to call them (proc vs procedure). Notice the space after "proc".
if @module_type = 'p'
begin
    select
         @file_content = replace(@file_content, 'create or alter proc ', 'create or alter procedure ')
        ,@file_content = replace(@file_content, 'create proc ', 'create procedure ')
        ,@file_content = replace(@file_content, 'alter proc ', 'alter procedure ')
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

if @module_type <> 'sc' -- SC = Script (Revisions, Post Processing, Tables, etc.)
begin
    -- Find the position of the module marker
    select @pos = pos
    from (
        select patindex('%' + m.module_definition + '%', @file_content) as pos
        from (
            select convert(char(2), 'p') as module_type, 'create procedure' as module_definition
            union select 'p', 'alter procedure'
            union select 'p', 'create or alter procedure'
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

--set @file_path = 'C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database\fmcsw\Post Processing\0100 Rollover SP_Log Table.sql'
set @file_path = 'C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database\FMCSW\Tables\sw.Schedule.sql'

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

--set @file_path = 'C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database\fmcsw\Revisions\Revisions_2.x.x.sql'
--set @file_path = 'C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database\Post Processing\9999 Remove Obsolete Routines.sql'
set @file_path = 'C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database\Post Processing\0100 Rollover SP_Log Table.sql'

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

--====================================================================================================

use master
go

if object_id('dbo.get_default_database_location') is not null
begin
    drop procedure dbo.get_default_database_location
end
go

create procedure dbo.get_default_database_location
(
     @default_data_path nvarchar(1000) = null output
    ,@default_log_path nvarchar(1000) = null output
    ,@debug tinyint = 0
)
with encryption
as

set nocount on
set xact_abort on
set transaction isolation level read uncommitted

/* Borrowed and modified from: http://www.dbi-services.com/index.php/blog/entry/sql-server-how-to-find-default-data-path */

/* Suggested @debug values
1 = Simple print statements
2 = Simple select statements (e.g. select @variable_1 as variable_1, @variable_2 as variable_2)
3 = Result sets from temp tables (e.g. select '#temp_table_name' as '#temp_table_name' from #temp_table_name where ...)
4 = @sql statements from exec() or sp_executesql
*/

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [get_default_database_location] START'

declare
     @position int
    ,@instance_name nvarchar(128)
    ,@registry_path nvarchar(128)
    ,@registry_key nvarchar(max)
    ,@database_name nvarchar(128)
    ,@sql nvarchar(1000)
    ,@sql_params nvarchar(200)

create table #instance_registry_path
(
     instance_name nvarchar(128)
    ,registry_path nvarchar(128)
)

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [get_default_database_location] Trying SERVERPROPERTY method'

-- If SQL Server 2012...
select
     @default_data_path = convert(nvarchar(128), serverproperty('instancedefaultdatapath'))
    ,@default_log_path = convert(nvarchar(128), serverproperty('instancedefaultlogpath'))

if @default_data_path is null
begin
    /* Must be SQL Server 2005 through 2008 */

    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [get_default_database_location] Trying registry method'

    -- Get the instance name
    set @position = charindex('\', @@servername)

    if @position = 0
        set @instance_name = N'MSSQLSERVER'
    else
        set @instance_name = substring(@@servername, @position + 1, len(@@servername))

    -- Pull the default path from the registry
    insert #instance_registry_path
        exec master.sys.xp_instance_regenumvalues N'HKEY_LOCAL_MACHINE', N'SOFTWARE\\Microsoft\\Microsoft SQL Server\\Instance Names\\SQL'

    select @registry_path = registry_path from #instance_registry_path where @instance_name = instance_name

    set @registry_key = N'SOFTWARE\Microsoft\Microsoft SQL Server\' + @registry_path + N'\MSSQLServer'

    exec master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @registry_key, N'DefaultData', @default_data_path output
    exec master.sys.xp_regread N'HKEY_LOCAL_MACHINE', @registry_key, N'DefaultLog', @default_log_path output

    if @default_data_path is null
    begin
        /* Wow, either something's *really* wrong or you're using a very old version of SQL Server! */

        if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [get_default_database_location] Trying any user database method'

        -- Look for the most recent, non-system database and see what they are using.
        select top 1 @database_name = name from sys.databases where database_id > 4 and name not in ('ReportServer', 'ReportServerTempDB') order by create_date desc

        if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [get_default_database_location] Getting physical_name from database [' + @database_name + ']'

        select
             @sql_params = N'@default_data_path nvarchar(1000) output, @default_log_path nvarchar(1000) output'
            ,@sql = N'select top 1 @default_data_path = physical_name from [<<@database_name>>].sys.database_files where type = 0; select top 1 @default_log_path = physical_name from [<<@database_name>>].sys.database_files where type = 1;'
            ,@sql = replace(@sql, '<<@database_name>>', @database_name)

        exec sp_executesql
             @sql, @sql_params
            ,@default_data_path = @default_data_path output
            ,@default_log_path = @default_log_path output

        if @default_data_path is null
        begin
            /* I guess we'll just use master. And if you don't have THAT then I'm out. */

            if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [get_default_database_location] Trying master database method'

            select
                 @sql_params = N'@default_data_path nvarchar(1000) output, @default_log_path nvarchar(1000) output'
                ,@sql = N'select top 1 @default_data_path = physical_name from [master].sys.database_files where type = 0; select top 1 @default_log_path = physical_name from [master].sys.database_files where type = 1;'

            exec sp_executesql
                 @sql, @sql_params
                ,@default_data_path = @default_data_path output
                ,@default_log_path = @default_log_path output
        end

        select
             @default_data_path = reverse(stuff(reverse(@default_data_path), 1, charindex('\', reverse(@default_data_path)), ''))
            ,@default_log_path = reverse(stuff(reverse(@default_log_path), 1, charindex('\', reverse(@default_log_path)), ''))
    end
end

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [get_default_database_location] END'

return 0

go

/* DEV TESTING

declare
     @default_data_path nvarchar(1000)
    ,@default_log_path nvarchar(1000)
    ,@debug tinyint = 9

exec master.dbo.get_default_database_location
     @default_data_path = @default_data_path output
    ,@default_log_path = @default_log_path output
    ,@debug = @debug

select @default_data_path as default_data_path, @default_log_path as default_log_path

*/

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
     @path varchar(260) -- Path to repository folder (i.e., C:\Users\username\Documents\GitHub\repository-name\) or the whatever you want to install folder (i.e., C:\Users\username\Documents\GitHub\repository-name\database\Bootstrap)
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

--====================================================================================================

use master
go

if object_id('dbo.install_tsqlt_class') is not null
begin
    drop procedure dbo.install_tsqlt_class
end
go

create procedure dbo.install_tsqlt_class
(
     @database_name nvarchar(128)       -- [Required] The database where you want to install the tSQLt class
    ,@file_path varchar(260)            -- [Required] Full path to the tSQLt.class.sql file
    ,@debug tinyint = 0
)
with encryption
as

/*

This will check for and install the tSQLt class to your database.

*/

set nocount on
--set xact_abort on -- disabled on purpose.
--set transaction isolation level read uncommitted -- not necessary.

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] START'

declare
     @return int = 0
    ,@sql nvarchar(1000)
    ,@sql_params nvarchar(100)
    ,@tsqlt_version_installed varchar(14)
    ,@tsqlt_version_release varchar(14)
    ,@xp_cmdshell nvarchar(4000)
    ,@server_name nvarchar(128) = @@servername
    ,@file_content nvarchar(max)
    ,@pos int
    ,@is_file bit

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] Running validate_path'

-- Validate path
exec @return = master.dbo.validate_path
     @path = @file_path
    ,@is_file = @is_file output
    ,@debug = @debug

if @is_file = 0
begin
    raiserror('Invalid path [%s].', 16, 1, @file_path)
    return @return
end

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] Running validate_database'

-- Make sure the database exists, etc.
exec @return = master.dbo.validate_database
     @database_name = @database_name
    ,@debug = @debug

if @return <> 0 return @return -- The previous call will throw an error so don't bother throwing another.

--====================================================================================================

-- This fixes a problem with restored databases and the tSQLt Class. Assumes that SA exists.

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] Changing owner of database to sa'

select
     @sql = N'alter authorization on database::[<<@database_name>>] to sa;'
    ,@sql = replace(@sql, '<<@database_name>>', @database_name)

if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] @sql: ' + isnull(@sql, '{null}')

exec @return = sp_executesql @sql

if @return <> 0 return @return

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] Setting trustworthy on'

select
     @sql = N'alter database [<<@database_name>>] set trustworthy on;'
    ,@sql = replace(@sql, '<<@database_name>>', @database_name)

if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] @sql: ' + isnull(@sql, '{null}')

exec @return = sp_executesql @sql

if @return <> 0 return @return

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] Get installed version number on [' + @database_name + ']'

select
     @sql_params = N'@tsqlt_version_installed varchar(14) output'
    ,@sql = N'if exists (select 1 from [<<@database_name>>].sys.schemas where name = ''tSQLt'') select @tsqlt_version_installed = [Version] from [<<@database_name>>].tSQLt.Info() else set @tsqlt_version_installed = 0'
    ,@sql = replace(@sql, '<<@database_name>>', @database_name)

if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] @sql: ' + isnull(@sql, '{null}')

-- Have to use Dynamic SQL because the database name could be different from the current database
exec @return = sp_executesql @sql, @sql_params, @tsqlt_version_installed = @tsqlt_version_installed output

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] @tsqlt_version_installed: ' + isnull(@tsqlt_version_installed, '{null}')

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] Get release version number'

exec master.dbo.read_file
     @file_path = @file_path
    ,@file_content = @file_content output
    ,@debug = @debug

-- Look for the version number/pattern
select @pos = patindex('%Version = ''[0-9].[0-9].%', @file_content)

if @pos > 0
    select @tsqlt_version_release = substring(@file_content, @pos + 11, 14)
else
    select @tsqlt_version_release = '0'

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] @tsqlt_version_release: ' + isnull(@tsqlt_version_release, '{null}')

--====================================================================================================

if @tsqlt_version_installed = '0' or (convert(bigint, replace(@tsqlt_version_release, '.', '')) > convert(bigint, replace(@tsqlt_version_installed, '.', '')))
begin
    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] Installing tSQLt.class.sql on [' + @database_name + ']'

    -- TODO: Change this to use the list_files, read_file, clean_file, parse_file logic so that you can count the number of GOs and make sure that all of the test classes and individual tests got installed.
    select
         -- If you add the -b switch (sqlcmd -b -E...) it will fail as soon as it runs into an error
         @xp_cmdshell = 'sqlcmd -E -S "<<@server_name>>" -d "<<@database_name>>" -I -i "<<@file_path>>"'
        ,@xp_cmdshell = replace(@xp_cmdshell, '<<@server_name>>', @server_name)
        ,@xp_cmdshell = replace(@xp_cmdshell, '<<@database_name>>', @database_name)
        ,@xp_cmdshell = replace(@xp_cmdshell, '<<@file_path>>', @file_path)

    if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] @xp_cmdshell: ' + isnull(@xp_cmdshell, '{null}')

    if @debug >= 255
        exec xp_cmdshell @xp_cmdshell
    else
        exec xp_cmdshell @xp_cmdshell, no_output

    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] Finished installing tSQLt.class.sql on [' + @database_name + ']'
end

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_class] END'

return @return

go

/*

use FMCSW_LOCAL
go

exec master.dbo.install_tsqlt_tests
     @database_name = 'FMCSW_LOCAL'
    ,@folder_path = 'C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database\fmcsw\Tests'
    ,@debug = 6

exec master.dbo.install_tsqlt_class
     @database_name = 'FMCSW_LOCAL'
    ,@file_path = 'C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database\fmcsw\Tests\tSQLt.class.sql'
    ,@debug = 6

*/

--====================================================================================================

use master
go

if object_id('dbo.install_tsqlt_tests') is not null
begin
    drop procedure dbo.install_tsqlt_tests
end
go

create procedure dbo.install_tsqlt_tests
(
     @database_name nvarchar(128)   -- [Required] The database where you want to install the tSQLt class
    ,@folder_path varchar(260)      -- [Required] Path to the folder containing the Tests (i.e., C:\Users\username\Documents\GitHub\repository-name\database\Tests)
    ,@debug tinyint = 0
)
with encryption
as

/*

This will look at the database folder and install all the tests for that database type (e.g., Portal, Case).

*/

set nocount on
--set xact_abort on -- disabled on purpose.
--set transaction isolation level read uncommitted -- not necessary.

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] START'

declare
     @return int = 0
    ,@xp_cmdshell nvarchar(4000)
    ,@server_name nvarchar(128) = @@servername
    ,@file_path varchar(260)
    ,@test_class nvarchar(max)
    ,@rowcount int

declare @output table (test_class nvarchar(max) null)

create table #loadoutput (ident int not null identity(1, 1) primary key clustered, ret_code int, test_class nvarchar(1000), command_output nvarchar(max))

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] Running validate_path'

set @folder_path = dbo.directory_slash(null, @folder_path, '\')

-- Validate path
exec @return = master.dbo.validate_path
     @path = @folder_path
    ,@is_file = 0
    ,@is_directory = 1
    ,@debug = @debug

if @return <> 0
begin
    raiserror('Invalid path [%s].', 16, 1, @folder_path)
    return @return
end

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] Running validate_database'

-- Make sure the database exists, etc.
exec @return = master.dbo.validate_database
     @database_name = @database_name
    ,@debug = @debug

if @return <> 0 return @return -- The previous call will throw an error so don't bother throwing another.

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] Running install_tsqlt_class on ' + @database_name

set @file_path = dbo.directory_slash(null, @folder_path, '\') + 'tSQLt.Class.sql'

exec @return = master.dbo.install_tsqlt_class
     @database_name = @database_name
    ,@file_path = @file_path
    ,@debug = @debug

if @return <> 0 return @return -- The previous call will throw an error so don't bother throwing another.

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] Getting all of the test classes.'

set @xp_cmdshell = 'dir /b "' + @folder_path + '\*.sql"'

if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] @xp_cmdshell: ' + isnull(@xp_cmdshell, '{null}')

insert @output (test_class)
    exec xp_cmdshell @xp_cmdshell

delete @output where test_class is null or test_class like 'File Not Found%' -- Happens when you don't have any procedures in a folder

delete @output where test_class = 'tSQLt.Class.sql'

select @rowcount = count(*) from @output

if @debug >= 5 select '@output' as '@output', * from @output

if exists (select 1 from @output where test_class = N'The system cannot find the file specified.')
begin
    raiserror('The system cannot find the path specified. Make sure @path is correct.', 16, 1)
    return -1
end

if exists (select 1 from @output where test_class = N'The device is not ready.')
begin
    raiserror('The device is not ready. Make sure @path is pointing to the correct drive letter.', 16, 1)
    return -1
end

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] Found ' + ltrim(str(@rowcount)) + ' test classes.'

--====================================================================================================

if @rowcount > 0
begin
    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] Installing test classes on ' + @database_name

    if exists (select 1 from sys.databases where name = @database_name)
    begin
        while exists (select 1 from @output)
        begin
            select top 1 @test_class = test_class, @xp_cmdshell = null from @output

            -- TODO: Change this to use the list_files, read_file, clean_file, parse_file logic so that you can count the number of GOs and make sure that all of the test classes and individual tests got installed.
            select
                 -- If you add the -b switch (sqlcmd -b -E...) it will fail as soon as it runs into an error
                 @xp_cmdshell = 'sqlcmd -b -E -S "<<@server_name>>" -d "<<@database_name>>" -I -i "<<@folder_path>>\<<@test_class>>"'
                ,@xp_cmdshell = replace(@xp_cmdshell, '<<@server_name>>', @server_name)
                ,@xp_cmdshell = replace(@xp_cmdshell, '<<@database_name>>', @database_name)
                ,@xp_cmdshell = replace(@xp_cmdshell, '<<@folder_path>>', @folder_path)
                ,@xp_cmdshell = replace(@xp_cmdshell, '<<@test_class>>', @test_class)

            if @debug >= 5 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] @xp_cmdshell: ' + isnull(@xp_cmdshell, '{null}')

            if @debug >= 255
                exec @return = xp_cmdshell @xp_cmdshell
            else
                exec @return = xp_cmdshell @xp_cmdshell, 'no_output'

            if @return <> 0
            begin
                insert into #loadoutput (command_output)
                    exec xp_cmdshell @xp_cmdshell

                update #loadoutput
                    set ret_code = @return
                        ,test_class = @test_class
                    where ret_code is null
            end

            delete @output where test_class = @test_class

            if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] Finished installing ' + @test_class + ' on ' + @database_name
        end
    end

    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] Finished installing the test classes.'
end

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [install_tsqlt_tests] END'

if exists (select 1 from #loadoutput)
    select ident, ret_code, test_class, command_output from #loadoutput where command_output is not null order by ident

return @return

go

/*

use FMCSW_LOCAL
go

exec master.dbo.upgrade_database
     @database_name = 'FMCSW_LOCAL'
    ,@folder_path = 'C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database\fmcsw\Tests'
    ,@debug = 1

exec master.dbo.install_tsqlt_tests
     @database_name = 'FMCSW_LOCAL'
    ,@folder_path = 'C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database\fmcsw\Tests'
    ,@debug = 1

-- Run all tSQLt tests
exec tSQLt.RunAll

*/

/*

-- Find the schema for any procedures that have "test" in the front and are not "dbo" and use tSQLt.DropClass to remove them.
-- Note: There's no easy way to find all of the tSQLt stored procedures because you can't assume that every non-dbo stored procedure is tSQLt. Someone could have created a stored procedure named "foo.bar".
-- A better method would be to restore a blank copy of the database and schema because someone could have created a real procedure named "foo.test-bar".
declare @sql nvarchar(4000) = N''

select @sql = @sql + 'exec tSQLt.DropClass ''' + schema_name([schema_id]) + '''
' from (select distinct [schema_id] from sys.procedures where is_ms_shipped = 0 and [schema_id] <> schema_id('dbo') and name like 'test%') x

exec sp_executesql @sql

*/

--====================================================================================================

use master
go

if object_id('dbo.upgrade_database') is not null
begin
    drop procedure dbo.upgrade_database
end
go

create procedure dbo.upgrade_database
(
     @database_name nvarchar(128)       -- [Required] Database name with or without brackets
    ,@folder_path varchar(260)          -- [Required] Path to the folder to install (i.e., C:\Users\username\Documents\GitHub\repository-name\folder)
    ,@folder_exclusions nvarchar(max)   -- Comma-separated list of folders to exclude (e.g., Build, Roles, Security)
    ,@file_exclusions nvarchar(max)     -- Comma-separated list of files to exclude (e.g., vwSchemaBoundView.sql, SpecialScriptFile.sql)
    ,@allow_system bit = 0              -- Allows installation on master for things like Ola H.'s tools, Brent Ozar's Blitz tools, etc.
    ,@debug tinyint = 0
)
with encryption
as

/*

This will look at the @folder_path and install all of the files to upgrade the database

*/

set nocount on
--set xact_abort on -- disabled on purpose.
--set transaction isolation level read uncommitted -- not necessary.

/* Suggested @debug values
1 = Simple print statements
2 = Simple select statements (e.g. select @variable_1 as variable_1, @variable_2 as variable_2)
3 = Result sets from temp tables (e.g. select '#temp_table_name' as '#temp_table_name', * from #temp_table_name where ...)
4 = @sql statements from exec() or sp_executesql
*/

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] START'

declare
     @return int = 0
    ,@rowcount int
    ,@ident int
    ,@database_folder_path varchar(260)
    ,@file_path varchar(260)
    ,@file_name varchar(260)
    ,@file_content nvarchar(max)
    ,@module_type char(2)
    ,@module_type_desc nvarchar(60)
    ,@module_name varchar(128)
    ,@sql nvarchar(max)
    ,@sql_statement nvarchar(max)
    ,@sql_params nvarchar(100)
    ,@object_exists bit
    ,@sort_by int

create table #TableOrder (SortBy smallint not null, TableName varchar(128) not null)

create table #ViewOrder (SortBy smallint not null, ViewName varchar(128) not null)

declare @files table ([file_path] nvarchar(260) null, [file_name] nvarchar(260) null, module_type char(2) null, module_name varchar(128) null, sortby int null)

declare @exclusions table (exclude nvarchar(260) not null)

declare @script table (ident int not null, sql_statement nvarchar(max) not null)

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Running validate_path'

set @database_folder_path = dbo.directory_slash(null, @folder_path, '\')

-- Validate path to the database folder in the repository
exec @return = master.dbo.validate_path
     @path = @database_folder_path
    ,@is_file = 0
    ,@is_directory = 1
    ,@debug = 0

if @return <> 0
begin
    raiserror('Invalid path [%s].', 16, 1, @database_folder_path)
    return @return
end

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Running validate_database'

-- Make sure the database exists, etc.
exec @return = master.dbo.validate_database
     @database_name = @database_name
    ,@allow_system = @allow_system
    ,@debug = @debug

if @return <> 0 return @return -- The previous call will throw an error so don't bother throwing another.

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Running list_files'

insert @files ([file_path])
    exec master.dbo.list_files
         @folder_path = @folder_path
        ,@include_subfolders = 1
        ,@extension = 'sql'
        ,@debug = @debug

delete @files where [file_path] is null

-- How many files do we have?
select @rowcount = count(*) from @files

if @debug >= 6 select '@files before' as [@files before], * from @files

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Found ' + ltrim(str(@rowcount)) + ' files.'

if exists (select 1 from @files where [file_path] = N'The system cannot find the file specified.')
begin
    set @return = -1
    raiserror('The system cannot find the path specified. Make sure @path is correct.', 16, 1)
    return @return
end

if exists (select 1 from @files where [file_path] = N'The device is not ready.')
begin
    set @return = -1
    raiserror('The device is not ready. Make sure @path is pointing to the correct drive letter.', 16, 1)
    return @return
end

if exists (select 1 from @files where [file_path] like 'File Not Found%')
begin
    set @return = -1
    raiserror('File Not Found. Make sure there SQL files in your @path.', 16, 1)
    return @return
end

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Removing unnecessary paths'

-- TODO: Assumes that you have at least two slashes (i.e., C:\repository-path\folder)
insert @exclusions (exclude) select distinct '%\%\' + Item + '%' from dbo.udf_split_8k_string_single_delimiter(@folder_exclusions, ',') where Item is not null

-- Ideally you would include the extension
insert @exclusions (exclude) select distinct '%\' + Item from dbo.udf_split_8k_string_single_delimiter(@file_exclusions, ',') where Item is not null

delete f from @files f join @exclusions e on f.file_path like e.exclude

set @rowcount = @@rowcount

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Removed ' + ltrim(str(@rowcount)) + ' files'

-- What do we have left?
select @rowcount = count(*) from @files

if @debug >= 5 select '@files after' as [@files after], * from @files

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] ' + ltrim(str(@rowcount)) + ' files remain after removing exclusions'

--====================================================================================================

if @rowcount > 0
begin
    -- Populate the file_name
    update @files set [file_name] = master.dbo.get_file_name_from_file_path([file_path]) where charindex('\', [file_path]) > 0

    -- The only thing we want in the module_name is the schema prefix.
    update @files set module_name = replace(replace([file_name], 'tsqlt.', ''), '.sql', '')

    -- Set the order
    -- TODO: Add Jobs, Roles, Users, Foreign Keys
    update @files set sortby = 10, module_type = 'sc' where [file_path] like '%\%\Schema%' and sortby is null
    update @files set sortby = 20, module_type = 'u' where [file_path] like '%\%\Tables\%TableOrder%' and sortby is null
    update @files set sortby = 30, module_type = 'u' where [file_path] like '%\%\Tables\%ViewOrder%' and sortby is null
    update @files set sortby = 40, module_type = 'sc' where [file_path] like '%\%\Static Data\%TableOrder%' and sortby is null
    update @files set sortby = 50, module_type = 'sc' where [file_path] like '%\%\Static Data\%ViewOrder%' and sortby is null
    update @files set sortby = 100, module_type = 'u' where [file_path] like '%\%\Tables%' and sortby is null -- We will sort them below
    update @files set sortby = 1000, module_type = 'sc' where [file_path] like '%\Foreign Keys\%DisableForeignKeys%' and sortby is null
    update @files set sortby = 2000, module_type = 'sc' where [file_path] like '%\%\Revisions%' and sortby is null
    update @files set sortby = 3000, module_type = 'sc' where [file_path] like '%\%\Static Data%' and sortby is null
    update @files set sortby = 3500, module_type = 'sc' where [file_path] like '%\Foreign Keys\%EnableForeignKeys%' and sortby is null
    update @files set sortby = 4000, module_type = 'fn' where [file_path] like '%\%\Functions%' and sortby is null
    update @files set sortby = 5000, module_type = 'v' where [file_path] like '%\%\Views%' and sortby is null -- We will sort them below
    update @files set sortby = 6000, module_type = 'p' where [file_path] like '%\%\Stored Procedures%' and sortby is null
    update @files set sortby = 7000, module_type = 'sc' where [file_path] like '%\%\Triggers%' and sortby is null
    update @files set sortby = 8000, module_type = 'sc' where [file_path] like '%\%\Jobs%' and sortby is null
    update @files set sortby = 9000, module_type = 'sc' where [file_path] like '%\%\Post Processing%' and sortby is null

    delete @files where sortby is null

    -- What do we have left now?
    select @rowcount = count(*) from @files

    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Installing ' + ltrim(str(@rowcount)) + ' files'

    if @debug >= 2 select '@files after sortby 1' as [@files after sortby], * from @files order by sortby

    -- First we have to run the files under 1000 to get the schema, TableOrder, and ViewOrder populated
    while exists (select 1 from @files)
    begin
        select top (1)
             @sort_by = sortby
            ,@file_path = [file_path]
            ,@file_name = [file_name]
            ,@module_type = module_type
            ,@module_type_desc = case module_type when 'v' then 'view' when 'fn' then 'function' when 'p' then 'procedure' when 'tr' then 'trigger' else null end
            ,@module_name = module_name
            ,@file_content = null
            ,@rowcount = 0
        from
            @files
        order by
            sortby

        if @debug >= 3
        begin
            print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @sort_by: ' + isnull(nullif(ltrim(str(@sort_by)), ''), '{null}')
            print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @file_path: ' + isnull(@file_path, '{null}')
            print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @file_name: ' + isnull(@file_name, '{null}')
            print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @module_type: ' + isnull(@module_type, '{null}')
            print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @module_type_desc: ' + isnull(@module_type_desc, '{null}')
            print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @module_name: ' + isnull(@module_name, '{null}')
        end

        -- Once the files with sortby <= 100 are loaded we need to update the sortby for Tables and Views
        if @sort_by = 100
        and (not exists (select 1 from #TableOrder) and not exists (select 1 from #ViewOrder)) -- Don't keep running this if the tables are already populated
        begin
            if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Populating #TableOrder'

            set @sql = N'if object_id(''[<<@database_name>>].dbo.TableOrder'') is not null select SortBy, TableName from [<<@database_name>>].dbo.TableOrder'

            set @sql = replace(@sql, '<<@database_name>>', @database_name)

            if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @sql: ' + isnull(@sql, '{null}')

            insert #TableOrder (SortBy, TableName) exec sp_executesql @sql

            set @rowcount = @@rowcount

            if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] ' + ltrim(str(@rowcount)) + ' row(s) added to #TableOrder'

            if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Populating #ViewOrder'

            set @sql = N'if object_id(''[<<@database_name>>].dbo.ViewOrder'') is not null select SortBy, ViewName from [<<@database_name>>].dbo.ViewOrder'

            set @sql = replace(@sql, '<<@database_name>>', @database_name)

            if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @sql: ' + isnull(@sql, '{null}')

            insert #ViewOrder (SortBy, ViewName) exec sp_executesql @sql

            set @rowcount = @@rowcount

            if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] ' + ltrim(str(@rowcount)) + ' row(s) added to #ViewOrder'

            if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Updating SortBy for Tables and Views'

            update f set sortby = 100 + o.SortBy, module_type = 'u' from @files f join #TableOrder o on f.module_name = o.TableName where f.[file_path] like '%\%\Tables%';

            set @rowcount = @@rowcount

            if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] ' + ltrim(str(@rowcount)) + ' row(s) updated in @files from #TableOrder for Tables'

            -- This is not really necessary because we remove all foreign keys to allow the Static Data to be added without worrying about the order.
            -- But, it should stop people from adding a "z" to the front of the file name in order to get it to load last.
            update f set sortby = 3000 + o.SortBy, module_type = 'sc' from @files f join #TableOrder o on f.module_name = o.TableName where f.[file_path] like '%\%\Static Data%';

            set @rowcount = @@rowcount

            if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] ' + ltrim(str(@rowcount)) + ' row(s) updated in @files from #TableOrder for Static Data'

            update f set sortby = 5000 + o.SortBy, module_type = 'v' from @files f join #ViewOrder o on f.module_name = o.ViewName where f.[file_path] like '%\%\Views%';

            set @rowcount = @@rowcount

            if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] ' + ltrim(str(@rowcount)) + ' row(s) updated in @files from #ViewOrder for Views'

            if @debug >= 5
            begin
                select '@files after sortby 2' as [@files after sortby], *
                from @files
                --where module_name in ('dbo.TAPRatioStates')
                order by sortby
            end
        end

        if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Running read_file on [' + isnull(@file_name, '{null}') + ']'

        exec @return = master.dbo.read_file
             @file_path = @file_path
            ,@file_content = @file_content output
            ,@debug = @debug

        if @return <> 0
        begin
            raiserror('Failed to read file [%s].', 16, 1, @file_name)
            return @return
        end

        if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Running clean_file on [' + isnull(@file_name, '{null}') + ']'

        exec @return = master.dbo.clean_file
             @module_type = @module_type
            ,@file_content = @file_content output
            ,@debug = @debug

        if @return <> 0
        begin
            raiserror('Failed to clean file [%s].', 16, 1, @file_name)
            return @return
        end

        -- TODO: Verify that the name of the file is the same as the name of the proc/function/trigger
        -- TODO: Verify schema

        -- Check to see if the object already exists (for certain module types)
        if @module_type in ('v','fn','p','tr','u')
        begin
            -- SQL 2016 SP1 introduced "create or alter {function|procedure|trigger|view}"
            if @module_type in ('v','fn','p','tr')
            begin
                if nullif(@module_type_desc, '') is not null
                begin
                    if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Change CREATE/ALTER to "create or alter"'

                    if @file_content not like 'create or alter %'
                    begin
                        set @file_content = replace(@file_content, 'alter ' + @module_type_desc, 'create or alter ' + @module_type_desc)
                        set @file_content = replace(@file_content, 'create ' + @module_type_desc, 'create or alter ' + @module_type_desc)
                    end

                    insert @script (ident, sql_statement) values (1, @file_content)

                    set @rowcount = @@rowcount
                end
            end
            else if @module_type in ('u')
            begin
                -- TODO: Handle brackets
                select
                     @sql_params = N'@object_exists bit = 0 output'
                    ,@sql = N'if object_id(''[<<@database_name>>].<<@module_name>>'') is not null set @object_exists = 1 else set @object_exists = 0'
                    ,@sql = replace(@sql, '<<@database_name>>', @database_name)
                    ,@sql = replace(@sql, '<<@module_name>>', @module_name)

                if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @sql: ' + isnull(@sql, '{null}')

                exec sp_executesql
                     @sql, @sql_params
                    ,@object_exists = @object_exists output

                if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @object_exists: ' + isnull(ltrim(str(@object_exists)), '{null}')

                -- If the table already exists then the Revisons script will fix it if needed. You can't use the Table.sql file to adjust the tables.
                if @object_exists = 0
                begin
                    insert @script (ident, sql_statement)
                        exec @return = master.dbo.parse_file
                             @file_content = @file_content
                            ,@debug = @debug

                    set @rowcount = @@rowcount
                end
            end
        end
        else if @module_type in ('sc') -- Always run Script files like Schema, Revisions, Post Processing
        begin
            insert @script (ident, sql_statement)
                exec @return = master.dbo.parse_file
                     @file_content = @file_content
                    ,@debug = @debug

            set @rowcount = @@rowcount
        end

        if @debug >= 6 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @file_content (first 100 characters): ' + left(isnull(@file_content, '{null}'), 100)
        if @debug >= 6 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @file_content (last 100 characters): ' + right(isnull(@file_content, '{null}'), 100)

        if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Installing file [' + @file_name + '] on [' + @database_name + ']'

        select
             @sql_params = N'@sql_statement nvarchar(max)'
            ,@sql = N'set quoted_identifier on; exec [<<@database_name>>].sys.sp_executesql @sql_statement;'
            ,@sql = replace(@sql, '<<@database_name>>', @database_name)

        set @ident = 1
        while @ident <= @rowcount
        begin
            select @ident = ident, @sql_statement = sql_statement from @script where ident = @ident

            if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @sql: ' + isnull(@sql, '{null}')
            if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @sql_statement: ' + isnull(@sql_statement, '{null}')

            exec @return = sp_executesql @sql, @sql_params, @sql_statement = @sql_statement

            if @return <> 0
            begin
                raiserror('Failed to install [%s].', 16, 1, @file_name)
                return @return
            end

            set @ident += 1
        end

        delete @files where [file_path] = @file_path
        delete @script
    end

    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Finished installing the files.'
end

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] END'

return @return

go

/* DEV TESTING

select routine_name, routine_type from master.information_schema.routines where routine_name in (
 'validate_repository'
,'get_default_database_location'
,'directory_slash'
,'list_files'
,'read_file'
,'validate_path'
,'upgrade_database'
)


select 'drop ' + routine_type + ' dbo.' + routine_name from master.information_schema.routines where routine_name in (
 'validate_repository'
,'get_default_database_location'
,'directory_slash'
,'list_files'
,'read_file'
,'validate_path'
,'upgrade_database'
)


drop FUNCTION dbo.directory_slash
drop PROCEDURE dbo.upgrade_database
drop PROCEDURE dbo.list_files
drop PROCEDURE dbo.read_file
drop PROCEDURE dbo.validate_path
drop PROCEDURE dbo.validate_repository

*/


/*

use FMCSW_LOCAL

--select 'FMCSW_LOCAL.sys.procedures before' as 'FMCSW_LOCAL.sys.procedures before', * from FMCSW_LOCAL.sys.procedures
--select 'master.sys.procedures before', * from master.sys.procedures

declare @return int

exec @return = master.dbo.upgrade_database
     @database_name = N'FMCSW_LOCAL'
    ,@folder_path = N'C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database\fmcsw'
    ,@folder_exclusions = 'Build,Bootstrap,Jobs,Roles,Scripts,Tests,Users'
    ,@file_exclusions = null
    ,@debug = 1

select @return as retval

-- declare @return int

exec @return = master.dbo.install_tsqlt_tests
     @database_name = 'FMCSW_LOCAL'
    ,@folder_path = 'C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database'
    ,@debug = 1

select @return as retval

--select 'FMCSW_LOCAL.sys.procedures after' as 'FMCSW_LOCAL.sys.procedures after', * from FMCSW_LOCAL.sys.procedures order by modify_date
--select 'master.sys.procedures after', * from master.sys.procedures

-- Run all tSQLt tests
exec tSQLt.RunAll

*/

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
     @database_name nvarchar(128)   -- [Required] Database name without brackets. TODO: Make this work with/without brackets.
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

--====================================================================================================

use master
go

if object_id('dbo.restore_database') is not null
begin
    drop procedure dbo.restore_database
end
go

create procedure dbo.restore_database
(
     @database_name nvarchar(128)               -- [Required] Does not have to be the same name as the backup. You can restore a Database.bak file as a database named "PaulHogan" if you want.
    ,@file_path nvarchar(4000) = null           -- [Optional] The full file path to the .bak file (e.g., D:\SQL\Backups\Database.bak). If not supplied we will look in the default location.
    ,@sql_data_directory nvarchar(500) = null   -- [Optional] Will use server default if not passed in.
    ,@sql_log_directory nvarchar(500) = null    -- [Optional] Will use server default if not passed in.
    ,@sql_ft_directory nvarchar(500) = null     -- [Optional] Will use server default if not passed in.
    ,@file_number tinyint = null                -- [Optional] Will use the max(file_number) if not passed in.
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

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [restore_database] START'

declare
     @return int = 0
    ,@header_sql nvarchar(max)
    ,@filelist_sql nvarchar(max)
    ,@restore_sql nvarchar(max)
    ,@default_data_path nvarchar(4000)
    ,@default_log_path nvarchar(4000)
    ,@sql_version int = convert(int, serverproperty('ProductMajorVersion'))
    ,@multi_path bit = 0
    ,@first_full_path nvarchar(4000)
    ,@directory nvarchar(4000) -- Directory only

create table #headeronly
(
     BackupName nvarchar(128) null
    ,BackupDescription nvarchar(255) null
    ,BackupType smallint null
    ,ExpirationDate datetime null
    ,Compressed bit null
    ,Position smallint null
    ,DeviceType tinyint null
    ,UserName nvarchar(128) null
    ,ServerName nvarchar(128) null
    ,DatabaseName nvarchar(128) null
    ,DatabaseVersion int null
    ,DatabaseCreationDate datetime null
    ,BackupSize numeric(20,0) null
    ,FirstLSN numeric(25,0) null
    ,LastLSN numeric(25,0) null
    ,CheckpointLSN numeric(25,0) null
    ,DatabaseBackupLSN numeric(25,0) null
    ,BackupStartDate datetime null
    ,BackupFinishDate datetime null
    ,SortOrder smallint null
    ,[CodePage] smallint null
    ,UnicodeLocaleId int null
    ,UnicodeComparisonStyle int null
    ,CompatibilityLevel tinyint null
    ,SoftwareVendorId int null
    ,SoftwareVersionMajor int null
    ,SoftwareVersionMinor int null
    ,SoftwareVersionBuild int null
    ,MachineName nvarchar(128) null
    ,Flags int null
    ,BindingID uniqueidentifier null
    ,RecoveryForkID uniqueidentifier null
    ,Collation nvarchar(128) null
    ,FamilyGUID uniqueidentifier null
    ,HasBulkLoggedData bit null
    ,IsSnapshot bit null
    ,IsReadOnly bit null
    ,IsSingleUser bit null
    ,HasBackupChecksums bit null
    ,IsDamaged bit null
    ,BeginsLogChain bit null
    ,HasIncompleteMetaData bit null
    ,IsForceOffline bit null
    ,IsCopyOnly bit null
    ,FirstRecoveryForkID uniqueidentifier null
    ,ForkPointLSN numeric(25,0) null
    ,RecoveryModel nvarchar(60) null
    ,DifferentialBaseLSN numeric(25,0) null
    ,DifferentialBaseGUID uniqueidentifier null
    ,BackupTypeDescription nvarchar(60) null
    ,BackupSetGUID uniqueidentifier null
    ,CompressedBackupSize numeric(20,0) null
    --,Containment tinyint not null -- SQL 2012+
)

create table #filelistonly
(
     ident int not null identity(1, 1) primary key clustered
    ,LogicalName varchar(255) null
    ,PhysicalName varchar(255) null
    ,[Type] char(1) null
    ,FileGroupName varchar(50) null
    ,Size bigint null
    ,MaxSize bigint null
    ,FileId int null
    ,CreateLSN numeric(30,2) null
    ,DropLSN numeric(30,2) null
    ,UniqueId uniqueidentifier null
    ,ReadOnlyLSN numeric(30,2) null
    ,ReadWriteLSN numeric(30,2) null
    ,BackupSizeInBytes bigint null
    ,SourceBlockSize int null
    ,FileGroupId int null
    ,LogGroupGUID uniqueidentifier null
    ,DifferentialBaseLSN numeric(30,2) null
    ,DifferentialBaseGUID uniqueidentifier null
    ,IsReadOnly int null
    ,IsPresent int null
    ,TDEThumbprint varchar(10) null
--    ,SnapshotUrl nvarchar(360) null -- SQL 2016+
)

declare @filelistonly table
(
     ident int not null primary key clustered
    ,LogicalName varchar(255) null
    ,PhysicalName varchar(255) null
    ,[Type] char(1) null
    ,FileGroupName varchar(50) null
    ,FileId int null
    ,FileGroupId int null
    ,NewLogicalName varchar(255) null
    ,NewPhysicalName varchar(255) null
    ,Directory varchar(255) null
)

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [restore_database] Product Major Version: ' + ltrim(str(@sql_version))

/*
11 = 2012
12 = 2014
13 = 2016
14 = 2017
*/

if @sql_version >= 14 -- SQL 2017
begin
    alter table #headeronly add Containment tinyint not null
    alter table #headeronly add KeyAlgorithm nvarchar(32) null
    alter table #headeronly add EncryptorThumbprint varbinary(20) null
    alter table #headeronly add EncryptorType nvarchar(32) null

    alter table #filelistonly add SnapshotUrl nvarchar(360) null
end
else if @sql_version >= 13 -- SQL 2016
begin
    alter table #filelistonly add SnapshotUrl nvarchar(360) null
end
else if @sql_version >= 11 -- SQL 2012
begin
    alter table #headeronly add Containment tinyint not null
end

select
     @sql_data_directory = nullif(@sql_data_directory, N'')
    ,@sql_log_directory = nullif(@sql_log_directory, N'')
    ,@sql_ft_directory = nullif(@sql_ft_directory, N'')

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [restore_database] Validating restore path'

if nullif(@file_path, '') is null -- The .bak name wasn't supplied either
begin
    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [restore_database] @file_path was empty. Checking registry for default location.'

    exec master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'BackupDirectory', @directory output, 'no_output'

    -- Now add @database_name and .bak to the @file_path
    set @file_path = @directory + N'\' + @database_name + N'.bak'
end
else
begin
    -- Remove the database name and extension (since they won't exist on the first backup) and just validate the directory. If @file_path wasn't supplied then this step isn't necessary.
    set @directory = substring(@file_path, 1, len(@file_path) - charindex('\', reverse(@file_path)))
end

-- TODO: Commenting out until I can fix the permission issues
--exec @return = master.dbo.validate_path
--     @path = @directory
--    ,@is_file = 1
--    ,@is_directory = 0
--    ,@debug = @debug

--if @return <> 0
--begin
--    raiserror('Invalid path [%s].', 16, 1, @directory)
--    return @return
--end

--====================================================================================================

if charindex(',', @file_path) > 0
begin
    set @multi_path = 1

    -- Grab the first path
    select @first_full_path = Item from master.dbo.udf_split_8k_string_single_delimiter(@file_path, ',') where ItemNumber = 1
end
else
begin
    set @first_full_path = @file_path
end

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [restore_database] Getting headers from ' + @file_path

select
     @header_sql = N'RESTORE HEADERONLY FROM DISK = N''<<@first_full_path>>''; '
    ,@header_sql = replace(@header_sql, N'<<@first_full_path>>', @first_full_path)

if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [restore_database] @header_sql: ' + isnull(@header_sql, N'{null}')

insert #headeronly
    exec(@header_sql)

if @debug >= 3 select '#headeronly before' as '#headeronly', * from #headeronly

if @file_number is null or @file_number < 1
begin
    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [restore_database] Getting maximum file_number (position)'

    select @file_number = max(position) from #headeronly
end

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [restore_database] Getting filelist from ' + @first_full_path

select
     @filelist_sql = N'RESTORE FILELISTONLY FROM DISK = N''<<@first_full_path>>'' WITH FILE = <<@file_number>>; '
    ,@filelist_sql = replace(@filelist_sql, N'<<@first_full_path>>', @first_full_path)
    ,@filelist_sql = replace(@filelist_sql, N'<<@file_number>>', @file_number)

if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [restore_database] @filelist_sql: ' + isnull(@filelist_sql, '{null}')

-- Don't need everything returned by FILELISTONLY but do need to add some additional columns for processing. Easier to just insert into another table (@filelistonly) instead of altering temp table.
insert #filelistonly
    exec(@filelist_sql)

if @debug >= 6 select '#filelistonly' as '#filelistonly', * from #filelistonly

insert @filelistonly (ident, LogicalName, PhysicalName, [Type], FileGroupName, FileId, FileGroupId)
    select ident, LogicalName, PhysicalName, [Type], FileGroupName, FileId, FileGroupId from #filelistonly

if @debug >= 3 select '@filelistonly before' as '@filelistonly', * from @filelistonly

--====================================================================================================

if @sql_data_directory is null or @sql_log_directory is null or @sql_ft_directory is null
begin
    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [restore_database] Find the default data and log paths'

    exec master.dbo.get_default_database_location
         @default_data_path = @default_data_path output
        ,@default_log_path = @default_log_path output
        ,@debug = @debug

    if @sql_data_directory is null set @sql_data_directory = @default_data_path
    if @sql_log_directory is null set @sql_log_directory = @default_log_path
    if @sql_ft_directory is null set @sql_ft_directory = @default_log_path

    if @debug >= 1
    begin
        print '[' + convert(varchar(23), getdate(), 121) + '] [restore_database] @sql_data_directory: ' + isnull(@sql_data_directory, N'{null}')
        print '[' + convert(varchar(23), getdate(), 121) + '] [restore_database] @sql_log_directory: ' + isnull(@sql_log_directory, N'{null}')
        print '[' + convert(varchar(23), getdate(), 121) + '] [restore_database] @sql_ft_directory: ' + isnull(@sql_ft_directory, N'{null}')
    end
end

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [restore_database] Setting SQL paths and database logical names'

update @filelistonly set Directory = '<<@sql_data_directory>>', NewLogicalName = '<<@database_name>>', NewPhysicalName = '<<@database_name>>.mdf' where [type] = 'D' and FileGroupName = 'PRIMARY' and FileId = 1
update @filelistonly set Directory = '<<@sql_data_directory>>', NewLogicalName = '<<@database_name>>_audit', NewPhysicalName = '<<@database_name>>_audit.ndf' where [type] = 'D' and FileGroupName = 'AUDIT'
update @filelistonly set Directory = '<<@sql_data_directory>>', NewLogicalName = '<<@database_name>>_indexes', NewPhysicalName = '<<@database_name>>_indexes.ndf' where [type] = 'D' and FileGroupName = 'INDEXES'
update @filelistonly set Directory = '<<@sql_data_directory>>', NewLogicalName = '<<@database_name>>_data', NewPhysicalName = '<<@database_name>>_data.ndf' where [type] = 'D' and FileGroupName = 'DATA'
update @filelistonly set Directory = '<<@sql_log_directory>>', NewLogicalName = '<<@database_name>>_log', NewPhysicalName = '<<@database_name>>_log.ldf' where [type] = 'L' and FileGroupId = 0
update @filelistonly set Directory = '<<@sql_ft_directory>>', NewLogicalName = '<<@database_name>>_fulltext', NewPhysicalName = '<<@database_name>>_fulltext.ndf' where [type] = 'F' or FileGroupName like '%OtherTables%' or LogicalName like 'ftrow[_]%'
update @filelistonly set Directory = '<<@sql_data_directory>>', NewLogicalName = '<<@database_name>>_temp_storage', NewPhysicalName = '<<@database_name>>_temp_storage.ndf' where [type] = 'D' and FileGroupName like '%Temp_Storage%'

if @debug >= 2 select '@filelistonly after' as '@filelistonly', * from @filelistonly

--====================================================================================================

-- Check for multiple file paths
if @multi_path = 1
begin
    set @restore_sql = N'RESTORE DATABASE [<<@database_name>>] FROM DISK = N''<<@first_full_path>>'''

    select @restore_sql = @restore_sql + N', DISK = N''' + Item + '''' from master.dbo.split_8k_string_single_delimiter(@file_path, ',') where ItemNumber > 1

    set @restore_sql = @restore_sql + N' WITH FILE = <<@file_number>>'
end
else
begin
    set @restore_sql = N'RESTORE DATABASE [<<@database_name>>] FROM DISK = N''<<@first_full_path>>'' WITH FILE = <<@file_number>>'
end

select @restore_sql = @restore_sql + ', MOVE N''' + LogicalName + ''' TO N''' + Directory + '' + NewPhysicalName + ''''
from @filelistonly

select
     @restore_sql = @restore_sql + ', NOUNLOAD, REPLACE, STATS = 10'
    ,@restore_sql = replace(@restore_sql, N'<<@database_name>>', @database_name)
    ,@restore_sql = replace(@restore_sql, N'<<@first_full_path>>', @first_full_path)
    ,@restore_sql = replace(@restore_sql, N'<<@file_number>>', @file_number)
    ,@restore_sql = replace(@restore_sql, N'<<@sql_data_directory>>', master.dbo.directory_slash(null, @sql_data_directory, N'\'))
    ,@restore_sql = replace(@restore_sql, N'<<@sql_log_directory>>', master.dbo.directory_slash(null, @sql_log_directory, N'\'))
    ,@restore_sql = replace(@restore_sql, N'<<@sql_ft_directory>>', master.dbo.directory_slash(null, @sql_ft_directory, N'\'))

if @debug >= 3 print '[' + convert(varchar(23), getdate(), 121) + '] [restore_database] @restore_sql (2): ' + isnull(@restore_sql, N'{null}')

if @restore_sql is null
begin
    raiserror('@restore_sql is null', 16, 1)
    return -1
end

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [restore_database] Running drop_database on [' + @database_name + ']'

-- By setting @debug to 255 you can skip the drop. Useful when you want to spit out the SQL at the bottom without actually running anything.
if @debug <> 255
begin
    exec master.dbo.drop_database
         @database_name = @database_name
        ,@debug = @debug
end

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [restore_database] Restoring database [' + @database_name + ']'

if @debug <> 255 exec sp_executesql @restore_sql

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [restore_database] END'

return @return

go

/* DEV TESTING

exec master.dbo.restore_database
     @database_name = 'foo'
    ,@file_path = 'D:\Databases\Database.bak' -- has 2 file numbers
    ,@sql_data_directory = 'D:\SQL\Data'
    ,@sql_log_directory = 'D:\SQL\Log'
    ,@sql_ft_directory = 'D:\SQL\FT'
    ,@file_number = 2
    ,@debug = 9

exec master.dbo.restore_database
     @database_name = 'foo_test'
    ,@file_path = 'D:\Databases\Database.bak' -- has 2 file numbers
    ,@debug = 255

*/

