--====================================================================================================

use master
go

create or alter function dbo.get_file_extension_from_file_name
(
     @file_name nvarchar(260)
)
returns varchar(260)
as
begin
    return right(@file_name, isnull(nullif(charindex(N'.', reverse(@file_name)), 0), 1) - 1) -- TODO: I don't like the isnull/nullif...good enough for now.
end
go

/* DEV TESTING

select dbo.get_file_extension_from_file_name('foo.sql')
select dbo.get_file_extension_from_file_name('foosql')

*/

