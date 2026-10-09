-- Run once in the SQL Editor of your own Supabase project.
-- No real financial records or credentials are included in this migration.
begin;
create table if not exists public.zhoujian_ledgers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  records jsonb not null default '[]'::jsonb check (jsonb_typeof(records) = 'array'),
  budget bigint not null default 200000 check (budget between 0 and 99999999900),
  version bigint not null default 0,
  operations jsonb not null default '[]'::jsonb check (jsonb_typeof(operations) = 'array'),
  updated_at timestamptz not null default now()
);
alter table public.zhoujian_ledgers enable row level security;
revoke all on public.zhoujian_ledgers from anon, authenticated;
grant select on public.zhoujian_ledgers to authenticated;
drop policy if exists zhoujian_read_own on public.zhoujian_ledgers;
create policy zhoujian_read_own on public.zhoujian_ledgers for select to authenticated
  using ((select auth.uid()) = user_id);

create or replace function public.zhoujian_valid_record(r jsonb) returns boolean
language plpgsql immutable set search_path = '' as $$
declare t text; c text; d date; amount bigint;
begin
  if r is null or jsonb_typeof(r) <> 'object' then return false; end if;
  if jsonb_typeof(r->'id') is distinct from 'string' or (r->>'id') !~ '^[A-Za-z0-9_-]{1,100}$' then return false; end if;
  if jsonb_typeof(r->'date') is distinct from 'string' or (r->>'date') !~ '^\d{4}-\d{2}-\d{2}$' then return false; end if;
  d := (r->>'date')::date;
  if to_char(d,'YYYY-MM-DD') <> r->>'date' or d < date '1900-01-01' or d > date '2200-12-31' then return false; end if;
  if jsonb_typeof(r->'cents') is distinct from 'number' or (r->>'cents') !~ '^\d+$' then return false; end if;
  amount := (r->>'cents')::bigint;
  if amount < 1 or amount > 99999999900 then return false; end if;
  t := r->>'type'; c := r->>'category';
  if t is null or c is null then return false; end if;
  if t = 'active' then
    if c <> all(array['工资薪酬','自由职业','兼职收入','奖金','其他收入']) then return false; end if;
  elsif t = 'passive' then
    if c <> all(array['利息收益','投资分红','租金收入','版税收入','其他收益']) then return false; end if;
  elsif t = 'expense' then
    if c <> all(array['餐饮美食','日常购物','交通出行','居家生活','休闲娱乐','医疗健康','学习成长','其他支出']) then return false; end if;
  else return false; end if;
  if jsonb_typeof(r->'account') is distinct from 'string' or r->>'account' <> all(array['微信钱包','支付宝','银行卡','现金','其他']) then return false; end if;
  if jsonb_typeof(r->'note') is distinct from 'string' or char_length(r->>'note') > 120 then return false; end if;
  return true;
exception when others then return false;
end;
$$;

create or replace function public.zhoujian_apply_operation(op jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid(); row_data public.zhoujian_ledgers%rowtype;
  kind text; operation_id text; record_id text; current_record jsonb; desired jsonb;
  new_records jsonb; new_operations jsonb; amount bigint; conflict boolean := false;
begin
  if uid is null then raise exception '请先登录' using errcode = '28000'; end if;
  if op is null or jsonb_typeof(op) <> 'object' or octet_length(op::text)>12000 then raise exception '请求格式无效' using errcode = '22023'; end if;
  operation_id := op->>'id'; kind := op->>'kind';
  if jsonb_typeof(op->'id') is distinct from 'string' or jsonb_typeof(op->'kind') is distinct from 'string' or operation_id is null or operation_id !~ '^[A-Za-z0-9_-]{1,100}$' or kind is null or kind <> all(array['upsert','delete','budget']) then raise exception '操作格式无效' using errcode = '22023'; end if;
  if kind = 'upsert' then
    if not public.zhoujian_valid_record(op->'record') or op->'base' is null or not (op->'base' = 'null'::jsonb or (public.zhoujian_valid_record(op->'base') and op->'base'->>'id' = op->'record'->>'id')) then raise exception '记录格式无效' using errcode = '22023'; end if;
    record_id := op->'record'->>'id';
    desired := jsonb_build_object('id',record_id,'date',op->'record'->>'date','type',op->'record'->>'type','cents',(op->'record'->>'cents')::bigint,'category',op->'record'->>'category','account',op->'record'->>'account','note',op->'record'->>'note');
  elsif kind = 'delete' then
    if not public.zhoujian_valid_record(op->'base') or op->>'recordId' is distinct from op->'base'->>'id' then raise exception '记录格式无效' using errcode = '22023'; end if;
    record_id := op->>'recordId';
  else
    if jsonb_typeof(op->'budget') is distinct from 'number' or jsonb_typeof(op->'baseBudget') is distinct from 'number' or (op->>'budget') !~ '^\d+$' or (op->>'baseBudget') !~ '^\d+$' then raise exception '预算格式无效' using errcode = '22023'; end if;
    amount := (op->>'budget')::bigint;
    if amount < 0 or amount > 99999999900 or (op->>'baseBudget')::bigint < 0 then raise exception '预算范围无效' using errcode = '22023'; end if;
  end if;
  insert into public.zhoujian_ledgers(user_id) values(uid) on conflict (user_id) do nothing;
  select * into row_data from public.zhoujian_ledgers where user_id = uid for update;
  if not (row_data.operations ? operation_id) then
    if kind = 'budget' then
      conflict := row_data.budget <> (op->>'baseBudget')::bigint and row_data.budget <> amount;
      if not conflict then row_data.budget := amount; end if;
    else
      select value into current_record from jsonb_array_elements(row_data.records) where value->>'id' = record_id limit 1;
      if kind = 'delete' and current_record is null then conflict := false;
      elsif kind = 'upsert' and current_record = desired then conflict := false;
      else
        conflict := coalesce(current_record,'null'::jsonb) is distinct from op->'base';
        if not conflict then
          select coalesce(jsonb_agg(value order by ord),'[]'::jsonb) into new_records
            from jsonb_array_elements(row_data.records) with ordinality as a(value,ord) where value->>'id' <> record_id;
          if kind = 'upsert' then
            if jsonb_array_length(new_records) >= 100000 then raise exception '记录数量已达上限' using errcode = '22023'; end if;
            new_records := new_records || jsonb_build_array(desired);
          end if;
          row_data.records := new_records;
        end if;
      end if;
    end if;
    if conflict then
      return jsonb_build_object('conflict',true,'error','同一记录已在另一台设备修改','records',row_data.records,'budget',row_data.budget,'version',row_data.version,'updatedAt',row_data.updated_at,'userId',uid);
    end if;
    select coalesce(jsonb_agg(value order by ord),'[]'::jsonb) into new_operations
      from jsonb_array_elements(row_data.operations) with ordinality as a(value,ord)
      where ord > greatest(0,jsonb_array_length(row_data.operations)-999);
    row_data.version := row_data.version + 1; row_data.updated_at := now();
    update public.zhoujian_ledgers set records=row_data.records,budget=row_data.budget,operations=new_operations || jsonb_build_array(operation_id),version=row_data.version,updated_at=row_data.updated_at where user_id=uid;
  end if;
  return jsonb_build_object('records',row_data.records,'budget',row_data.budget,'version',row_data.version,'updatedAt',row_data.updated_at,'userId',uid);
end;
$$;
revoke all on function public.zhoujian_valid_record(jsonb) from public, anon, authenticated;
revoke all on function public.zhoujian_apply_operation(jsonb) from public, anon, authenticated;
grant execute on function public.zhoujian_apply_operation(jsonb) to authenticated;
commit;
