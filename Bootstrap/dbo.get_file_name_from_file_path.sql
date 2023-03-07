--====================================================================================================

use master
go

create or alter function dbo.get_file_name_from_file_path
(
     @file_path nvarchar(260)
)
returns varchar(260)
as
begin
    return right(@file_path, isnull(nullif(charindex(N'\', reverse(@file_path)), 0), 1) - 1) -- TODO: I don't like the isnull/nullif...good enough for now.
end
go

/* DEV TESTING

select master.dbo.get_file_name_from_file_path('c:\temp\foo.sql')
select master.dbo.get_file_name_from_file_path('foo.sql')
*/

