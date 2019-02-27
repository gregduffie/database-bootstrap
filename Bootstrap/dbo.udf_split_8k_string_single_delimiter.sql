--====================================================================================================

use master
go

if object_id('dbo.udf_split_8k_string_single_delimiter') is not null
begin
    drop function dbo.udf_split_8k_string_single_delimiter
end
go

create function dbo.udf_split_8k_string_single_delimiter
(
     @string varchar(8000)
    ,@delimiter char(1) = ','
)
--WARNING!!! DO NOT USE MAX DATA-TYPES HERE! IT WILL KILL PERFORMANCE!
--This method produces zero reads compared to rs_fn_splitNVARCHAR
returns table with schemabinding as
return

/*
Taken from Jeff Moden's article:
http://www.sqlservercentral.com/articles/Tally+Table/72993/
*/

with e1(n) as
( -- 10E+1 or 10 rows
    select 1 union all select 1 union all select 1 union all
    select 1 union all select 1 union all select 1 union all
    select 1 union all select 1 union all select 1 union all select 1
)
,e2(n) as
( -- 10E+2 or 100 rows
    select 1 from e1 a, e1 b
)
,e4(n) as
( -- 10E+4 or 10,000 rows max
    select 1 from e2 a, e2 b
)
,cteTally(n) as
( -- This provides the base CTE and limits the number of rows right up front for both a performance gain and prevention of accidental overruns
    select top (isnull(datalength(@string),0)) row_number() over (order by (select null)) from e4
),
cteStart(n1) as
( -- This returns N+1 (starting position of each element just once for each delimiter)
    select 1 union all
    select t.n + 1 from cteTally t where substring(@string, t.n, 1) = @delimiter
),
cteLen(n1, l1) as
( -- Return start and length (for use in substring)
    select s.n1, isnull(nullif(charindex(@delimiter, @string, s.n1), 0) - s.n1, 8000)
    from cteStart s
)
-- Do the actual split. The ISNULLNULLIF combo handles the length for the final element when no delimiter is found.
select
     ItemNumber = row_number() over(order by l.n1)
    ,Item = substring(@string, l.n1, l.l1)
from cteLen l;

go

/*

declare
     @string varchar(8000) = 'D:\temp\temp_1.sql,D:\temp\temp_2.sql,D:\temp\temp_3.sql'
    ,@delimiter char(1) = ','

select * from dbo.udf_split_8k_string_single_delimiter(@string, @delimiter)

*/
