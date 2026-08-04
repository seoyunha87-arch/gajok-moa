-- 실시간 동기화를 위해 테이블을 supabase_realtime 발행 목록에 추가합니다.
-- (이미 추가되어 있어도 에러 없이 넘어가도록 처리했습니다.)

do $$
begin
  alter publication supabase_realtime add table public.profiles;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.events;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.albums;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.photos;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.notifications;
exception when duplicate_object then null;
end $$;
