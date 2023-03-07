--====================================================================================================

use master
go

create or alter procedure dbo.validate_path
(
     @path nvarchar(260)                    -- [Required] A folder/directory or full file path including the file name and extension.
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

if nullif(@path, N'') is null
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

