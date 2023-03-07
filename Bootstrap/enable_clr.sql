--====================================================================================================

use master
go

exec sys.sp_configure @configname = 'clr enabled', @configvalue = 1
go

reconfigure
go

if convert(int, serverproperty('ProductMajorVersion')) >= 14
begin
    exec sys.sp_configure @configname = 'clr strict security', @configvalue = 0

    reconfigure
end
go

