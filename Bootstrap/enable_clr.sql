--====================================================================================================

use master
go

exec sp_configure 'clr enabled', 1
go

reconfigure
go

if convert(int, serverproperty('ProductMajorVersion')) >= 14
begin
    exec sp_configure 'clr strict security', 0

    reconfigure
end
go

