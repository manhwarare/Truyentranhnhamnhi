-- NÂNG CẤP v2: sắp xếp theo lượt truy cập (tổng / ngày / tuần / tháng) + "mới cập nhật" theo chương mới
-- Chạy file này trong Supabase > SQL Editor (an toàn khi chạy lại, không mất dữ liệu).

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
