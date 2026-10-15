-- Eje · esquema para Supabase
-- Pegá este archivo completo en el SQL Editor de tu proyecto y ejecutalo.
-- Se puede volver a ejecutar sin perder datos.
--
-- Modelo de seguridad: las tablas no se pueden leer ni escribir directo con la
-- clave pública (RLS activado, sin políticas). Todo pasa por las funciones de
-- abajo, que validan un token de sesión emitido al entrar con código + apodo + PIN.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.eje_groups (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique,
  name       text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.eje_members (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.eje_groups(id) on delete cascade,
  alias        text not null,
  pin_hash     text not null,
  failed       int  not null default 0,
  locked_until timestamptz,
  cfg          jsonb,
  cfg_updated  bigint not null default 0,
  share_on     boolean not null default true,
  share        jsonb,
  created_at   timestamptz not null default now()
);
create unique index if not exists eje_members_alias_uq on public.eje_members (group_id, lower(alias));

create table if not exists public.eje_sessions (
  member_id uuid   not null references public.eje_members(id) on delete cascade,
  id        text   not null,
  ts        bigint not null default 0,
  data      jsonb  not null,
  primary key (member_id, id)
);

create table if not exists public.eje_tokens (
  token      uuid primary key default gen_random_uuid(),
  member_id  uuid not null references public.eje_members(id) on delete cascade,
  created_at timestamptz not null default now(),
  used_at    timestamptz not null default now()
);
create index if not exists eje_tokens_member on public.eje_tokens (member_id);

alter table public.eje_groups   enable row level security;
alter table public.eje_members  enable row level security;
alter table public.eje_sessions enable row level security;
alter table public.eje_tokens   enable row level security;
revoke all on public.eje_groups, public.eje_members, public.eje_sessions, public.eje_tokens from anon, authenticated;

-- ---------- interna: token -> miembro (vence a los 180 días sin uso) ----------
create or replace function public.eje_member(p_token uuid)
returns uuid language sql security definer set search_path = public as $$
  update eje_tokens set used_at = now()
   where token = p_token and used_at > now() - interval '180 days'
  returning member_id;
$$;
revoke execute on function public.eje_member(uuid) from public, anon, authenticated;

-- ---------- entrar (o crear perfil) ----------
create or replace function public.eje_join(p_code text, p_alias text, p_pin text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  g eje_groups;
  m eje_members;
  v_alias text := left(btrim(coalesce(p_alias, '')), 30);
  v_tok uuid;
  v_new boolean := false;
begin
  select * into g from eje_groups where code = upper(btrim(coalesce(p_code, '')));
  if not found then return jsonb_build_object('error', 'group'); end if;
  if length(v_alias) < 2 then return jsonb_build_object('error', 'alias'); end if;
  if coalesce(p_pin, '') !~ '^[0-9]{4,8}$' then return jsonb_build_object('error', 'pin_format'); end if;

  select * into m from eje_members where group_id = g.id and lower(alias) = lower(v_alias);
  if not found then
    if (select count(*) from eje_members where group_id = g.id) >= 50 then
      return jsonb_build_object('error', 'full');
    end if;
    insert into eje_members (group_id, alias, pin_hash)
    values (g.id, v_alias, crypt(p_pin, gen_salt('bf')))
    returning * into m;
    v_new := true;
  else
    if m.locked_until is not null and m.locked_until > now() then
      return jsonb_build_object('error', 'locked');
    end if;
    if m.pin_hash <> crypt(p_pin, m.pin_hash) then
      -- 5 intentos fallidos bloquean ese apodo 15 minutos
      update eje_members
         set failed       = case when failed + 1 >= 5 then 0 else failed + 1 end,
             locked_until = case when failed + 1 >= 5 then now() + interval '15 minutes' else locked_until end
       where id = m.id;
      return jsonb_build_object('error', 'pin');
    end if;
    update eje_members set failed = 0, locked_until = null where id = m.id;
  end if;

  insert into eje_tokens (member_id) values (m.id) returning token into v_tok;
  return jsonb_build_object(
    'token', v_tok, 'member', m.id, 'alias', m.alias, 'new', v_new,
    'group', jsonb_build_object('code', g.code, 'name', g.name));
end $$;

-- ---------- crear grupo ----------
create or replace function public.eje_create_group(p_name text, p_alias text, p_pin text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_name text := left(btrim(coalesce(p_name, '')), 40);
  v_code text;
  abc text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  i int;
begin
  if length(v_name) < 2 then return jsonb_build_object('error', 'name'); end if;
  if length(btrim(coalesce(p_alias, ''))) < 2 then return jsonb_build_object('error', 'alias'); end if;
  if coalesce(p_pin, '') !~ '^[0-9]{4,8}$' then return jsonb_build_object('error', 'pin_format'); end if;
  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(abc, 1 + floor(random() * length(abc))::int, 1);
    end loop;
    exit when not exists (select 1 from eje_groups where code = v_code);
  end loop;
  insert into eje_groups (code, name) values (v_code, v_name);
  return eje_join(v_code, p_alias, p_pin);
end $$;

-- ---------- datos propios ----------
create or replace function public.eje_load(p_token uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := eje_member(p_token); r jsonb;
begin
  if v is null then return jsonb_build_object('error', 'auth'); end if;
  select jsonb_build_object(
           'alias', m.alias, 'share_on', m.share_on, 'cfg', m.cfg, 'cfg_updated', m.cfg_updated,
           'group', jsonb_build_object('code', g.code, 'name', g.name),
           'sessions', coalesce((select jsonb_agg(s.data order by s.ts desc)
                                   from eje_sessions s where s.member_id = m.id), '[]'::jsonb))
    into r
    from eje_members m join eje_groups g on g.id = m.group_id
   where m.id = v;
  return r;
end $$;

create or replace function public.eje_save_cfg(p_token uuid, p_cfg jsonb, p_updated bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := eje_member(p_token);
begin
  if v is null then return jsonb_build_object('error', 'auth'); end if;
  if octet_length(p_cfg::text) > 500000 then return jsonb_build_object('error', 'size'); end if;
  update eje_members set cfg = p_cfg, cfg_updated = p_updated
   where id = v and cfg_updated <= p_updated;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.eje_save_session(p_token uuid, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := eje_member(p_token);
begin
  if v is null then return jsonb_build_object('error', 'auth'); end if;
  if coalesce(p_data->>'id', '') = '' then return jsonb_build_object('error', 'id'); end if;
  if octet_length(p_data::text) > 200000 then return jsonb_build_object('error', 'size'); end if;
  insert into eje_sessions (member_id, id, ts, data)
  values (v, p_data->>'id', coalesce((p_data->>'ts')::bigint, 0), p_data)
  on conflict (member_id, id) do update set ts = excluded.ts, data = excluded.data;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.eje_delete_session(p_token uuid, p_id text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := eje_member(p_token);
begin
  if v is null then return jsonb_build_object('error', 'auth'); end if;
  delete from eje_sessions where member_id = v and id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- ---------- grupo ----------
create or replace function public.eje_set_share(p_token uuid, p_on boolean, p_share jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := eje_member(p_token);
begin
  if v is null then return jsonb_build_object('error', 'auth'); end if;
  if octet_length(coalesce(p_share::text, '')) > 300000 then return jsonb_build_object('error', 'size'); end if;
  update eje_members
     set share_on = coalesce(p_on, false),
         share    = case when coalesce(p_on, false) then p_share else null end
   where id = v;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.eje_group(p_token uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := eje_member(p_token); r jsonb;
begin
  if v is null then return jsonb_build_object('error', 'auth'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'alias', o.alias, 'share', o.share) order by o.alias), '[]'::jsonb)
    into r
    from eje_members me
    join eje_members o on o.group_id = me.group_id
   where me.id = v and o.share_on and o.share is not null;
  return r;
end $$;

-- ---------- sesión y baja ----------
create or replace function public.eje_logout(p_token uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  delete from eje_tokens where token = p_token;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.eje_delete_me(p_token uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := eje_member(p_token); g uuid;
begin
  if v is null then return jsonb_build_object('error', 'auth'); end if;
  select group_id into g from eje_members where id = v;
  delete from eje_members where id = v;  -- borra también sesiones y tokens
  delete from eje_groups where id = g and not exists (select 1 from eje_members where group_id = g);
  return jsonb_build_object('ok', true);
end $$;

-- Funciones que la app puede llamar con la clave pública
grant execute on function
  public.eje_join(text, text, text),
  public.eje_create_group(text, text, text),
  public.eje_load(uuid),
  public.eje_save_cfg(uuid, jsonb, bigint),
  public.eje_save_session(uuid, jsonb),
  public.eje_delete_session(uuid, text),
  public.eje_set_share(uuid, boolean, jsonb),
  public.eje_group(uuid),
  public.eje_logout(uuid),
  public.eje_delete_me(uuid)
to anon, authenticated;
