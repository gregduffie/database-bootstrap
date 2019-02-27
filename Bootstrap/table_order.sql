
-- TODO: BCP out the results to the TableOrder.csv file

-- https://stackoverflow.com/questions/40388903/how-to-list-tables-in-their-dependency-order-based-on-foreign-keys
with cte (lvl, object_id, name)
as
(
    select
         1
        ,object_id
        ,name
    from
        sys.tables
    where
        type_desc = 'USER_TABLE'
        and is_ms_shipped = 0
    union all
    select
        cte.lvl + 1
        ,t.object_id
        ,t.name
    from
        cte
    join
        sys.tables t
        on exists
            (
                select
                    null
                from
                    sys.foreign_keys fk
                where
                    fk.parent_object_id = t.object_id
                    and fk.referenced_object_id = cte.object_id
            )
            and t.object_id <> cte.object_id
            and cte.lvl < 30
    where
        t.type_desc = 'USER_TABLE'
        and t.is_ms_shipped = 0
)
select
    cte.name
   ,max(cte.lvl) as dependency_level
from
    cte
group by
    cte.name
order by
    dependency_level
   ,cte.name
