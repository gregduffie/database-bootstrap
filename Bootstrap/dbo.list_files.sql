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
     @folder_path varchar(260)      -- [Required] Path to folder (i.e., C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database\)
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
     @folder_path = 'C:\Users\gduffie\Documents\GitHub\fmc-schedulewise-database\database\revisions\Revisions_2.x.x.sql'
    ,@include_subfolders = 1
    ,@extension = 'sql'
    ,@debug = 2

*/
