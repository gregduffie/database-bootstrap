--====================================================================================================

use master
go

create or alter procedure dbo.validate_repository
(
     @repository_path nvarchar(2000)    -- [Required] The full path to the base of the repository (e.g., C:\Users\username\Documents\GitHub\repository-name) where the (hidden) .git folder is located.
    ,@branch nvarchar(50) = null         -- [Optional] The branch that you are expecting to be checked out (i.e., "ref: refs/heads/development").
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
    ,@file_path nvarchar(260)
    ,@file_content nvarchar(max)
    ,@head nvarchar(200)

-- Add a slash to the end if needed
set @repository_path = master.dbo.directory_slash(null, @repository_path, N'\')

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

set @file_path = @repository_path + N'.git\HEAD'

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
    set @head = N'ref: refs/heads/' + @branch

    if charindex(@head, @file_content) = 0
    begin
        set @return = -1
        raiserror(N'[%s] does not contain the [%s] branch in the HEAD file.', 16, 1, @file_path, @branch)
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

