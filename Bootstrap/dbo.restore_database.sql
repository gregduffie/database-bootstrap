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
    ,@full_path nvarchar(4000) = null           -- [Optional] The full path to the .bak file (e.g., D:\SQL\Backups\Database.bak). If not supplied we will look in the default location.
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
    ,@sql nvarchar(max)
    ,@header_sql nvarchar(max)
    ,@filelist_sql nvarchar(max)
    ,@restore_sql nvarchar(max)
    ,@default_data_path nvarchar(4000)
    ,@default_log_path nvarchar(4000)
    ,@sql_version varchar(20) = convert(varchar(20), serverproperty('productversion'))
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
    ,DifferentialBaseGUID uniqueidentifier
    ,BackupTypeDescription nvarchar(60) null
    ,BackupSetGUID uniqueidentifier null
    ,CompressedBackupSize numeric(20,0) null
    --,Containment tinyint not null -- SQL 2012+
)

-- SQL 2012+ added a new column
if left(@sql_version, charindex('.', @sql_version) - 1) >= 11
begin
    alter table #headeronly add Containment tinyint not null
end

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

select
     @sql_data_directory = nullif(@sql_data_directory, N'')
    ,@sql_log_directory = nullif(@sql_log_directory, N'')
    ,@sql_ft_directory = nullif(@sql_ft_directory, N'')

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [restore_database] Validating restore path'

if nullif(@full_path, '') is null -- The .bak name wasn't supplied either
begin
    if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [restore_database] @full_path was empty. Checking registry for default location.'

    exec master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'BackupDirectory', @directory output, 'no_output'

    -- Now add @database_name and .bak to the @full_path
    set @full_path = @directory + N'\' + @database_name + N'.bak'
end
else
begin
    -- Remove the database name and extension (since they won't exist on the first backup) and just validate the directory. If @full_path wasn't supplied then this step isn't necessary.
    set @directory = substring(@full_path, 1, len(@full_path) - charindex('\', reverse(@full_path)))
end

exec @return = master.dbo.rp_validate_path
     @path = @directory
    ,@debug = @debug

--====================================================================================================

if charindex(',', @full_path) > 0
begin
    set @multi_path = 1

    -- Grab the first path
    select @first_full_path = Item from master.dbo.rf_split_8k_string_single_delimiter(@full_path, ',') where ItemNumber = 1
end
else
begin
    set @first_full_path = @full_path
end

--====================================================================================================

if @debug >= 1 print '[' + convert(varchar(23), getdate(), 121) + '] [restore_database] Getting headers from ' + @full_path

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

    exec master.dbo.rp_get_default_database_location
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

    select @restore_sql = @restore_sql + N', DISK = N''' + Item + '''' from master.dbo.rf_split_8k_string_single_delimiter(@full_path, ',') where ItemNumber > 1

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
    ,@restore_sql = replace(@restore_sql, N'<<@sql_data_directory>>', master.dbo.rf_directory_slash(null, @sql_data_directory, N'\'))
    ,@restore_sql = replace(@restore_sql, N'<<@sql_log_directory>>', master.dbo.rf_directory_slash(null, @sql_log_directory, N'\'))
    ,@restore_sql = replace(@restore_sql, N'<<@sql_ft_directory>>', master.dbo.rf_directory_slash(null, @sql_ft_directory, N'\'))

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
    ,@full_path = 'D:\Databases\Database.bak' -- has 2 file numbers
    ,@sql_data_directory = 'D:\SQL\Data'
    ,@sql_log_directory = 'D:\SQL\Log'
    ,@sql_ft_directory = 'D:\SQL\FT'
    ,@file_number = 2
    ,@debug = 9

exec master.dbo.restore_database
     @database_name = 'foo_test'
    ,@full_path = 'D:\Databases\Database.bak' -- has 2 file numbers
    ,@debug = 255

*/
