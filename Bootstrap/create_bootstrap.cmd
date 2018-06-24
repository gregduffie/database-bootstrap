del Database.Bootstrap.sql
copy /b enable_xpcmdshell.sql + enable_clr.sql + dbo.directory_slash.sql + dbo.get_file_name_from_file_path.sql + dbo.get_file_extension_from_file_name.sql + dbo.validate_path.sql + dbo.validate_repository.sql + dbo.validate_database.sql + dbo.list_files.sql + dbo.read_file.sql + dbo.clean_file.sql + dbo.parse_file.sql + dbo.create_database.sql + dbo.install_tsqlt_class.sql + dbo.install_tsqlt_tests.sql + dbo.upgrade_database.sql Database.Bootstrap.sql
pause
