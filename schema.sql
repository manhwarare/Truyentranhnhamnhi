-- Chạy toàn bộ file này trong Supabase > SQL Editor
create extension if not exists pgcrypto;

create table comics (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  slug text unique not null,
  author text,
  description text,
  cover_url text,
  status text not null default 'ongoing' check (status in ('ongoing','completed')),
  genres text[] not null default '{}',
  views bigint not null default 0,
  created_at timestamptz not null default now()
);

create table chapters (
  id uuid primary key default gen_random_uuid(),
  comic_id uuid not null references comics(id) on delete cascade,
  number numeric not null,
  title text,
  pages text[] not null default '{}',
  created_at timestamptz not null default now(),
  unique (comic_id, number)
);

create table admins (user_id uuid primary key references auth.users(id) on delete cascade);

create or replace function is_admin() returns boolean
language sql security definer set search_path = public stable as
$$ select exists (select 1 from admins where user_id = auth.uid()) $$;

create or replace function increment_views(comic uuid) returns void
language sql security definer set search_path = public as
$$ update comics set views = views + 1 where id = comic $$;

alter table comics enable row level security;
alter table chapters enable row level security;
alter table admins enable row level security;

create policy "đọc công khai" on comics for select using (true);
create policy "admin ghi" on comics for all using (is_admin()) with check (is_admin());
create policy "đọc công khai" on chapters for select using (true);
create policy "admin ghi" on chapters for all using (is_admin()) with check (is_admin());
create policy "tự kiểm tra quyền" on admins for select using (user_id = auth.uid());

-- Kho ảnh công khai
insert into storage.buckets (id, name, public) values ('comics','comics',true) on conflict do nothing;
create policy "xem ảnh" on storage.objects for select using (bucket_id = 'comics');
create policy "admin tải ảnh" on storage.objects for insert with check (bucket_id = 'comics' and is_admin());
create policy "admin sửa ảnh" on storage.objects for update using (bucket_id = 'comics' and is_admin());
create policy "admin xoá ảnh" on storage.objects for delete using (bucket_id = 'comics' and is_admin());

-- SAU KHI tạo user admin ở Authentication > Users, chạy (thay email):
-- insert into admins select id from auth.users where email = 'ban@example.com';
