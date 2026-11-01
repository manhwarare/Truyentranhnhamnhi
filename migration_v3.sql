-- NÂNG CẤP v3: tài khoản người đọc, lưu tiến độ đọc, theo dõi truyện, xếp hạng "Hot", lọc thể loại/trạng thái
-- Chạy file này trong Supabase > SQL Editor (đã chạy migration.sql / v2 trước). An toàn khi chạy lại, không mất dữ liệu.

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
