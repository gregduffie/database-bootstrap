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
    ,@debug tinyint = 0
)
with encryption
as

/*

This will look at the repository location and install all of the files to upgrade the database

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

--create table #TableOrder ([name] varchar(128) not null, dependency_level tinyint not null)

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
    ,@debug = 1

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

    -- Kinda cheating here...
    update @files set module_name = replace(replace(replace([file_name], 'dbo.', ''), 'tsqlt.', ''), '.sql', '')

    --if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Populate TableOrder'

    --set xact_abort on
    -- TODO: Change this to use the repo path + '\Tables\TableOrder.csv'
    --bulk insert #TableOrder from 'C:\Users\username\Documents\GitHub\repository-name\database\Tables\TableOrder.csv' with (datafiletype = 'char', firstrow = 2, tablock, format = 'csv')
    --set xact_abort off

    --if @debug >= 4 select '#TableOrder' as [#TableOrder], * from #TableOrder

    -- Set the order
    -- TODO: Add Jobs, Roles, Users
    --update f set sortby = (10 * o.dependency_level), module_type = 'u' from @files f join #TableOrder o on f.module_name = o.[name] where f.[file_path] like '%\Tables%'
    update @files set sortby = 200, module_type = 'sc' where [file_path] like '%\%\Static Data%'
    --update @files set sortby = 300, module_type = 'fk' where [file_path] like '%\Foreign Keys%'
    update @files set sortby = 400, module_type = 'sc' where [file_path] like '%\%\Revisions%'
    update @files set sortby = 500, module_type = 'fn' where [file_path] like '%\%\Functions%'
    update @files set sortby = 600, module_type = 'v' where [file_path] like '%\%\Views%'
    update @files set sortby = 700, module_type = 'p' where [file_path] like '%\%\Stored Procedures%'
    update @files set sortby = 900, module_type = 'sc' where [file_path] like '%\%\Triggers%'
    update @files set sortby = 800, module_type = 'sc' where [file_path] like '%\%\Post Processing%'

    delete @files where sortby is null

    -- What do we have left now?
    select @rowcount = count(*) from @files

    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Installing ' + ltrim(str(@rowcount)) + ' files'

    if @debug >= 5 select '@files after sortby' as [@files after sortby], * from @files order by sortby

    while exists (select 1 from @files)
    begin
        select top (1)
             @file_path = [file_path]
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
            print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @file_path: ' + isnull(@file_path, '{null}')
            print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @file_name: ' + isnull(@file_name, '{null}')
            print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @module_type: ' + isnull(@module_type, '{null}')
            print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @module_type_desc: ' + isnull(@module_type_desc, '{null}')
            print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @module_name: ' + isnull(@module_name, '{null}')
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

        if @module_type in ('v','fn','p','tr')
        begin
            select
                 @sql_params = N'@module_type char(2), @module_name nvarchar(128), @object_exists bit = 0 output'
                ,@sql = N'if exists (select 1 from [<<@database_name>>].sys.objects where [name] = @module_name) set @object_exists = 1 else set @object_exists = 0'
                ,@sql = replace(@sql, '<<@database_name>>', @database_name)

            if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @sql: ' + isnull(@sql, '{null}')

            exec sp_executesql
                 @sql, @sql_params
                ,@module_type = @module_type
                ,@module_name = @module_name
                ,@object_exists = @object_exists output

            if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @object_exists: ' + isnull(ltrim(str(@object_exists)), '{null}')

            if @object_exists = 1 and nullif(@module_type_desc, '') is not null
            begin
                if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Change CREATE to ALTER'

                -- Change CREATE to ALTER
                set @file_content = replace(@file_content, 'create ' + @module_type_desc, 'alter ' + @module_type_desc)
            end
            else
            begin
                if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Change ALTER to CREATE'

                -- Change ALTER to CREATE
                set @file_content = replace(@file_content, 'alter ' + @module_type_desc, 'create ' + @module_type_desc)
            end

            insert @script (ident, sql_statement) values (1, @file_content)

            set @rowcount = @@rowcount
        end
        else if @module_type in ('sc', 'u')
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

use Sandbox

--select 'Sandbox.sys.procedures before' as 'Sandbox.sys.procedures before', * from Sandbox.sys.procedures
--select 'master.sys.procedures before', * from master.sys.procedures

declare @return int

exec @return = master.dbo.upgrade_database
     @database_name = N'Sandbox'
    ,@folder_path = N'C:\Users\username\Documents\GitHub\repository-name\folder'
    ,@folder_exclusions = 'Build,Bootstrap,Jobs,Roles,Scripts,Tests,Users'
    ,@file_exclusions = 'dbo.ZipCodeLookup.sql,dbo.JSONHierarchy.sql,dbo.udf_ToJSON.sql,dbo.vwScheduleStartTime.sql,dbo.vwScheduleEndTime.sql,dbo.vwSchedule.sql'
    ,@debug = 1

select @return as retval

-- declare @return int

exec @return = master.dbo.install_tsqlt_tests
     @database_name = 'Sandbox'
    ,@folder_path = 'C:\Users\username\Documents\GitHub\repository-name'
    ,@debug = 1

select @return as retval

--select 'Sandbox.sys.procedures after' as 'Sandbox.sys.procedures after', * from Sandbox.sys.procedures order by modify_date
--select 'master.sys.procedures after', * from master.sys.procedures

-- Run all tSQLt tests
exec tSQLt.RunAll

*/

