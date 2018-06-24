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

