--====================================================================================================

use master
go

create or alter function dbo.udf_split_unicode_string_single_delimiter
(
     @string nvarchar(max)
    ,@delimiter nchar(1) = N','
)
returns table with schemabinding as
return

-- The values will always be in left-to-right order, but we need ItemNumber for certain queries that require a sort order.
-- You can use any internal function (e.g., db_name(), getdate(), @@version) or even a variable (e.g., @string, @delimiter) to do the same thing,
-- but I used @@spid so it would seem unusual and force you to read this comment. ;-)
-- You can't use "1" or null or anything like that or you'll get an "Windowed functions, aggregates and NEXT VALUE FOR functions do not support integer indices as ORDER BY clause expressions." error.
select row_number() over (order by @@spid) as ItemNumber, [value] as Item from string_split(@string, @delimiter)

go

/* DEV TESTING

declare
     @string varchar(8000) = 'D:\temp\temp_1.sql,D:\temp\temp_2.sql,D:\temp\temp_3.sql'
    ,@delimiter char(1) = ','

select * from dbo.udf_split_unicode_string_single_delimiter(@string, @delimiter)

*/

