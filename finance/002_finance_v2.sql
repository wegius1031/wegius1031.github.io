-- Generic schema only. Contains no private financial data.
begin;
create table if not exists public.weekly_wallet_documents (
 user_id uuid primary key references auth.users(id) on delete cascade,
 data jsonb not null,
 version bigint not null default 1,
 receipts jsonb not null default '[]'::jsonb,
 updated_at timestamptz not null default now(),
 check(jsonb_typeof(data)='object' and octet_length(data::text)<=10000000)
);
alter table public.weekly_wallet_documents enable row level security;
revoke all on public.weekly_wallet_documents from anon,authenticated;
grant select on public.weekly_wallet_documents to authenticated;
drop policy if exists wallet_read_own on public.weekly_wallet_documents;
create policy wallet_read_own on public.weekly_wallet_documents for select to authenticated using ((select auth.uid())=user_id);
create or replace function public.weekly_wallet_save(document jsonb,expected_version bigint,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); row_data public.weekly_wallet_documents%rowtype; r jsonb; s jsonb; d date;
begin
 if uid is null then raise exception '请先登录' using errcode='28000';end if;
 if request_id is null or expected_version is null or expected_version<0 or document is null or jsonb_typeof(document)<>'object' or octet_length(document::text)>10000000 or document->>'schemaVersion' is distinct from '2'
 or jsonb_typeof(document->'records') is distinct from 'array' or jsonb_typeof(document->'snapshots') is distinct from 'array'
 or (document->>'reserve') !~ '^\d+$' or (document->>'reserve')::numeric>99999999900 or document->'reserve' is null
 then raise exception '账本格式无效' using errcode='22023';end if;
 if jsonb_array_length(document->'records')>10000 or jsonb_array_length(document->'snapshots')>1000 then raise exception '记录数量过多';end if;
 for r in select value from jsonb_array_elements(document->'records') loop
  if coalesce(r->>'id','') !~ '^[A-Za-z0-9_-]{1,100}$' or coalesce(r->>'date','') !~ '^\d{4}-\d{2}-\d{2}$'
  or coalesce(r->>'amount','') !~ '^\d+$' or (r->>'amount')::numeric<1 or (r->>'amount')::numeric>99999999900
  or coalesce(r->>'kind','') <> all(array['income','expense','buy','sell','dividend','transfer','borrow','repay'])
  or jsonb_typeof(r->'account') is distinct from 'string' or char_length(r->>'account')>80
  or jsonb_typeof(r->'category') is distinct from 'string' or char_length(r->>'category')>100
  or jsonb_typeof(r->'note') is distinct from 'string' or char_length(r->>'note')>120 then raise exception '交易格式无效';end if;
  d:=(r->>'date')::date;if to_char(d,'YYYY-MM-DD')<>r->>'date' or d<date '1900-01-01' or d>date '2200-12-31' then raise exception '日期无效';end if;
 end loop;
 if (select count(distinct value->>'id') from jsonb_array_elements(document->'records'))<>jsonb_array_length(document->'records') then raise exception '交易编号重复';end if;
 for s in select value from jsonb_array_elements(document->'snapshots') loop
  if coalesce(s->>'id','') !~ '^[A-Za-z0-9_-]{1,100}$' or coalesce(s->>'date','') !~ '^\d{4}-\d{2}-\d{2}$'
  or jsonb_typeof(s->'accounts') is distinct from 'array' or jsonb_typeof(s->'holdings') is distinct from 'array'
  or coalesce(s->>'debt','') !~ '^\d+$' or (s->>'debt')::numeric>99999999900 then raise exception '快照格式无效';end if;
  d:=(s->>'date')::date;if to_char(d,'YYYY-MM-DD')<>s->>'date' then raise exception '快照日期无效';end if;
 end loop;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,0));
 select * into row_data from public.weekly_wallet_documents where user_id=uid for update;
 if found then
  if row_data.receipts ? request_id::text then return jsonb_build_object('data',row_data.data,'version',row_data.version);end if;
  if row_data.version<>expected_version then return jsonb_build_object('conflict',true,'data',row_data.data,'version',row_data.version);end if;
  update public.weekly_wallet_documents set data=document,version=version+1,receipts=(select coalesce(jsonb_agg(value),'[]'::jsonb) from (select value from jsonb_array_elements(row_data.receipts||jsonb_build_array(request_id::text)) with ordinality as x(value,n) order by n desc limit 50) q),updated_at=now() where user_id=uid returning * into row_data;
 else
  if expected_version<>0 then return jsonb_build_object('conflict',true,'data',null,'version',0);end if;
  insert into public.weekly_wallet_documents(user_id,data,receipts) values(uid,document,jsonb_build_array(request_id::text)) returning * into row_data;
 end if;
 return jsonb_build_object('data',row_data.data,'version',row_data.version);
end;
$$;
revoke all on function public.weekly_wallet_save(jsonb,bigint,uuid) from public,anon;
grant execute on function public.weekly_wallet_save(jsonb,bigint,uuid) to authenticated;
commit;
