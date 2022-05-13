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

