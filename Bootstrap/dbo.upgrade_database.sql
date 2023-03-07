--====================================================================================================

use master
go

create or alter procedure dbo.upgrade_database
(
     @database_name nvarchar(128)       -- [Required] Database name with or without brackets
    ,@folder_path nvarchar(260)         -- [Required] Path to the folder to install (i.e., C:\Users\username\Documents\GitHub\repository-name\folder)
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
    ,@database_folder_path nvarchar(260)
    ,@file_path nvarchar(260)
    ,@file_name nvarchar(260)
    ,@file_content nvarchar(max)
    ,@module_type char(2)
    ,@module_type_desc nvarchar(60)
    ,@module_name nvarchar(128)
    ,@sql nvarchar(max)
    ,@sql_statement nvarchar(max)
    ,@sql_params nvarchar(100)
    ,@object_exists bit
    ,@sort_by int

create table #TableOrder (SortBy smallint not null, TableName nvarchar(128) not null)

create table #ViewOrder (SortBy smallint not null, ViewName nvarchar(128) not null)

declare @files table ([file_path] nvarchar(260) null, [file_name] nvarchar(260) null, module_type char(2) null, module_name nvarchar(128) null, sortby int null)

declare @exclusions table (exclude nvarchar(260) not null)

declare @script table (ident int not null, sql_statement nvarchar(max) not null)

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Running validate_path'

set @database_folder_path = dbo.directory_slash(null, @folder_path, N'\')

-- Validate path to the database folder in the repository
exec @return = master.dbo.validate_path
     @path = @database_folder_path
    ,@is_file = 0
    ,@is_directory = 1
    ,@debug = 0

if @return <> 0
begin
    raiserror(N'Invalid path [%s].', 16, 1, @database_folder_path)
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
        ,@extension = N'sql'
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

if exists (select 1 from @files where [file_path] like N'File Not Found%')
begin
    set @return = -1
    raiserror('File Not Found. Make sure there SQL files in your @path.', 16, 1)
    return @return
end

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Removing unnecessary paths'

-- TODO: Assumes that you have at least two slashes (i.e., C:\repository-path\folder)
insert @exclusions (exclude) select distinct N'%\%\' + Item + N'%' from dbo.udf_split_unicode_string_single_delimiter(@folder_exclusions, N',') where Item is not null

-- Ideally you would include the extension
insert @exclusions (exclude) select distinct N'%\' + Item from dbo.udf_split_unicode_string_single_delimiter(@file_exclusions, N',') where Item is not null

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
    update @files set module_name = replace(replace([file_name], N'tsqlt.', N''), N'.sql', N'')

    -- Set the order
    -- TODO: Add Jobs, Roles, Users, Foreign Keys
    update @files set sortby = 10, module_type = 'sc' where [file_path] like N'%\%\Schema%' and sortby is null
    update @files set sortby = 20, module_type = 'u' where [file_path] like N'%\%\Tables\%TableOrder%' and sortby is null
    update @files set sortby = 30, module_type = 'u' where [file_path] like N'%\%\Tables\%ViewOrder%' and sortby is null
    update @files set sortby = 40, module_type = 'sc' where [file_path] like N'%\%\Static Data\%TableOrder%' and sortby is null
    update @files set sortby = 50, module_type = 'sc' where [file_path] like N'%\%\Static Data\%ViewOrder%' and sortby is null
    update @files set sortby = 100, module_type = 'u' where [file_path] like N'%\%\Tables%' and sortby is null -- We will sort them below
    update @files set sortby = 1000, module_type = 'sc' where [file_path] like N'%\Foreign Keys\%DisableForeignKeys%' and sortby is null
    update @files set sortby = 2000, module_type = 'sc' where [file_path] like N'%\%\Revisions%' and sortby is null
    update @files set sortby = 3000, module_type = 'sc' where [file_path] like N'%\%\Static Data%' and sortby is null
    update @files set sortby = 3500, module_type = 'sc' where [file_path] like N'%\Foreign Keys\%EnableForeignKeys%' and sortby is null
    update @files set sortby = 4000, module_type = 'fn' where [file_path] like N'%\%\Functions%' and sortby is null
    update @files set sortby = 5000, module_type = 'v' where [file_path] like N'%\%\Views%' and sortby is null -- We will sort them below
    update @files set sortby = 5500, module_type = 'tt' where [file_path] like N'%\%\Types%' and sortby is null -- Do not put the schema in front of the file name or it will not run.
    update @files set sortby = 6000, module_type = 'p' where [file_path] like N'%\%\Stored Procedures%' and sortby is null
    update @files set sortby = 7000, module_type = 'sc' where [file_path] like N'%\%\Triggers%' and sortby is null
    update @files set sortby = 8000, module_type = 'sc' where [file_path] like N'%\%\Jobs%' and sortby is null
    update @files set sortby = 9000, module_type = 'sc' where [file_path] like N'%\%\Post Processing%' and sortby is null

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

            set @sql = replace(@sql, N'<<@database_name>>', @database_name)

            if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @sql: ' + isnull(@sql, '{null}')

            insert #TableOrder (SortBy, TableName) exec sp_executesql @sql

            set @rowcount = @@rowcount

            if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] ' + ltrim(str(@rowcount)) + ' row(s) added to #TableOrder'

            if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Populating #ViewOrder'

            set @sql = N'if object_id(''[<<@database_name>>].dbo.ViewOrder'') is not null select SortBy, ViewName from [<<@database_name>>].dbo.ViewOrder'

            set @sql = replace(@sql, N'<<@database_name>>', @database_name)

            if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @sql: ' + isnull(@sql, '{null}')

            insert #ViewOrder (SortBy, ViewName) exec sp_executesql @sql

            set @rowcount = @@rowcount

            if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] ' + ltrim(str(@rowcount)) + ' row(s) added to #ViewOrder'

            if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Updating SortBy for Tables and Views'

            update f set sortby = 100 + o.SortBy, module_type = 'u' from @files f join #TableOrder o on f.module_name = o.TableName where f.[file_path] like N'%\%\Tables%';

            set @rowcount = @@rowcount

            if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] ' + ltrim(str(@rowcount)) + ' row(s) updated in @files from #TableOrder for Tables'

            -- This is not really necessary because we remove all foreign keys to allow the Static Data to be added without worrying about the order.
            -- But, it should stop people from adding a "z" to the front of the file name in order to get it to load last.
            update f set sortby = 3000 + o.SortBy, module_type = 'sc' from @files f join #TableOrder o on f.module_name = o.TableName where f.[file_path] like N'%\%\Static Data%';

            set @rowcount = @@rowcount

            if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] ' + ltrim(str(@rowcount)) + ' row(s) updated in @files from #TableOrder for Static Data'

            update f set sortby = 5000 + o.SortBy, module_type = 'v' from @files f join #ViewOrder o on f.module_name = o.ViewName where f.[file_path] like N'%\%\Views%';

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
            raiserror(N'Failed to read file [%s].', 16, 1, @file_name)
            return @return
        end

        if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Running clean_file on [' + isnull(@file_name, '{null}') + ']'

        exec @return = master.dbo.clean_file
             @module_type = @module_type
            ,@file_content = @file_content output
            ,@debug = @debug

        if @return <> 0
        begin
            raiserror(N'Failed to clean file [%s].', 16, 1, @file_name)
            return @return
        end

        -- TODO: Verify that the name of the file is the same as the name of the proc/function/trigger
        -- TODO: Verify schema

        -- Check to see if the object already exists (for certain module types)
        if @module_type in ('v','fn','p','tr','u','tt')
        begin
            -- SQL 2016 SP1 introduced "create or alter {function|procedure|trigger|view}"
            if @module_type in ('v','fn','p','tr')
            begin
                if nullif(@module_type_desc, '') is not null
                begin
                    if @debug >= 2 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] Change CREATE/ALTER to "create or alter"'

                    if @file_content not like N'create or alter %'
                    begin
                        set @file_content = replace(@file_content, N'alter ' + @module_type_desc, N'create or alter ' + @module_type_desc)
                        set @file_content = replace(@file_content, N'create ' + @module_type_desc, N'create or alter ' + @module_type_desc)
                    end

                    insert @script (ident, sql_statement) values (1, @file_content)

                    set @rowcount = @@rowcount
                end
            end
            else if @module_type in ('u','tt')
            begin
                -- TODO: Handle brackets
                if @module_type = 'u'
                    set @sql = N'if object_id(''[<<@database_name>>].<<@module_name>>'') is not null set @object_exists = 1 else set @object_exists = 0'
                else if @module_type = 'tt'
                    set @sql = N'if exists (select 1 from [<<@database_name>>].sys.table_types where is_user_defined = 1 and name = ''<<@module_name>>'') set @object_exists = 1 else set @object_exists = 0'

                select
                     @sql_params = N'@object_exists bit = 0 output'
                    ,@sql = replace(@sql, N'<<@database_name>>', @database_name)
                    ,@sql = replace(@sql, N'<<@module_name>>', @module_name)

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
            ,@sql = replace(@sql, N'<<@database_name>>', @database_name)

        set @ident = 1
        while @ident <= @rowcount
        begin
            select @ident = ident, @sql_statement = sql_statement from @script where ident = @ident

            if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @sql: ' + isnull(@sql, '{null}')
            if @debug >= 4 print '[' + convert(varchar(23), getdate(), 121) + '] [upgrade_database] @sql_statement: ' + isnull(@sql_statement, '{null}')

            exec @return = sp_executesql @sql, @sql_params, @sql_statement = @sql_statement

            if @return <> 0
            begin
                raiserror(N'Failed to install [%s].', 16, 1, @file_name)
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
    ,@file_exclusions = 'dbo.vwScheduleStartTime.sql,dbo.vwScheduleEndTime.sql,dbo.vwSchedule.sql'
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

