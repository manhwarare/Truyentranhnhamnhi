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

-- ===== v2: lượt truy cập & sắp xếp (cùng nội dung migration.sql) =====

-- 1. Thời điểm cập nhật: tự đổi mỗi khi có chương mới
alter table comics add column if not exists updated_at timestamptz not null default now();
update comics c set updated_at = coalesce((select max(created_at) from chapters where comic_id = c.id), c.created_at);

create or replace function touch_comic() returns trigger
language plpgsql security definer set search_path = public as
$$ begin update comics set updated_at = now() where id = new.comic_id; return new; end $$;
drop trigger if exists chapters_touch on chapters;
create trigger chapters_touch after insert on chapters for each row execute function touch_comic();

-- 2. Nhật ký lượt xem (để tính top ngày/tuần/tháng). Không có policy: chỉ hàm bên dưới truy cập được.
create table if not exists comic_views (
  id bigint generated always as identity primary key,
  comic_id uuid not null references comics(id) on delete cascade,
  viewed_at timestamptz not null default now()
);
create index if not exists comic_views_time_idx on comic_views (viewed_at, comic_id);
alter table comic_views enable row level security;

-- 3. Mỗi lượt xem: cộng vào tổng và ghi nhật ký
create or replace function increment_views(comic uuid) returns void
language sql security definer set search_path = public as
$$
  update comics set views = views + 1 where id = comic;
  insert into comic_views (comic_id) select comic where exists (select 1 from comics where id = comic);
$$;

-- 4. Bảng xếp hạng theo khoảng thời gian (days = 1, 7, 30…)
create or replace function top_comics(days int, lim int default 60)
returns table (id uuid, title text, slug text, cover_url text, author text, status text, views bigint)
language sql stable security definer set search_path = public as
$$
  select c.id, c.title, c.slug, c.cover_url, c.author, c.status, count(v.id)::bigint
  from comics c join comic_views v on v.comic_id = c.id
  where v.viewed_at > now() - make_interval(days => days)
  group by c.id order by 7 desc, c.created_at desc limit lim
$$;
grant execute on function top_comics(int, int) to anon, authenticated;

-- (Tuỳ chọn) dọn nhật ký cũ hơn 90 ngày:  delete from comic_views where viewed_at < now() - interval '90 days';



-- 1. Tiến độ đọc: mỗi người, mỗi truyện giữ 1 dòng = chương đọc gần nhất
create table if not exists reading_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  comic_id uuid not null references comics(id) on delete cascade,
  chapter_id uuid not null references chapters(id) on delete cascade,
  chapter_number numeric,
  updated_at timestamptz not null default now(),
  primary key (user_id, comic_id)
);
create index if not exists reading_progress_user_time on reading_progress (user_id, updated_at desc);

-- 2. Các chương đã đọc (để đánh dấu trong danh sách chương)
create table if not exists read_chapters (
  user_id uuid not null references auth.users(id) on delete cascade,
  chapter_id uuid not null references chapters(id) on delete cascade,
  comic_id uuid not null references comics(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (user_id, chapter_id)
);
create index if not exists read_chapters_user_comic on read_chapters (user_id, comic_id);

-- 3. Theo dõi truyện
create table if not exists follows (
  user_id uuid not null references auth.users(id) on delete cascade,
  comic_id uuid not null references comics(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, comic_id)
);
create index if not exists follows_comic_time on follows (comic_id, created_at);

-- 4. Phân quyền: mỗi người chỉ thấy và sửa dữ liệu của chính mình
alter table reading_progress enable row level security;
alter table read_chapters enable row level security;
alter table follows enable row level security;

drop policy if exists "tiến độ của tôi" on reading_progress;
create policy "tiến độ của tôi" on reading_progress for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "chương đã đọc của tôi" on read_chapters;
create policy "chương đã đọc của tôi" on read_chapters for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "theo dõi của tôi" on follows;
create policy "theo dõi của tôi" on follows for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- 5. Top ngày/tuần/tháng: thêm lọc theo thể loại + trạng thái (đổi kiểu trả về nên phải drop bản cũ)
drop function if exists top_comics(int, int);
create or replace function top_comics(days int, lim int default 60, p_genre text default null, p_status text default null)
returns table (id uuid, title text, slug text, cover_url text, author text, status text, views bigint, genres text[])
language sql stable security definer set search_path = public as
$$
  select c.id, c.title, c.slug, c.cover_url, c.author, c.status, count(v.id)::bigint, c.genres
  from comics c join comic_views v on v.comic_id = c.id
  where v.viewed_at > now() - make_interval(days => days)
    and (p_genre is null or p_genre = any(c.genres))
    and (p_status is null or c.status = p_status)
  group by c.id order by 7 desc, c.created_at desc limit lim
$$;
grant execute on function top_comics(int, int, text, text) to anon, authenticated;

-- 6. Độ "Hot": lượt xem gần đây có trọng số (hôm nay x5, 7 ngày x2, 30 ngày x1) + mỗi lượt theo dõi mới trong 30 ngày x10
create or replace function hot_comics(lim int default 60, p_genre text default null, p_status text default null)
returns table (id uuid, title text, slug text, cover_url text, author text, status text, views bigint, genres text[], score bigint)
language sql stable security definer set search_path = public as
$$
  select c.id, c.title, c.slug, c.cover_url, c.author, c.status, c.views, c.genres,
    ( count(*) filter (where v.viewed_at > now() - interval '1 day') * 5
    + count(*) filter (where v.viewed_at > now() - interval '7 days') * 2
    + count(*)
    + coalesce((select count(*) from follows f where f.comic_id = c.id and f.created_at > now() - interval '30 days'), 0) * 10
    )::bigint as score
  from comics c join comic_views v on v.comic_id = c.id
  where v.viewed_at > now() - interval '30 days'
    and (p_genre is null or p_genre = any(c.genres))
    and (p_status is null or c.status = p_status)
  group by c.id order by score desc, c.created_at desc limit lim
$$;
grant execute on function hot_comics(int, text, text) to anon, authenticated;

-- (Tuỳ chọn) Supabase > Authentication > Providers > Email: tắt "Confirm email" nếu muốn đăng ký xong đọc được ngay.
