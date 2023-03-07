--====================================================================================================

use master
go

-- To allow advanced options to be changed.
exec sys.sp_configure @configname = 'show advanced options', @configvalue = 1
go

-- To update the currently configured value for advanced options.
reconfigure
go

-- To enable the feature.
exec sys.sp_configure @configname = 'xp_cmdshell', @configvalue = 1
go

-- To update the currently configured value for this feature.
reconfigure
go

