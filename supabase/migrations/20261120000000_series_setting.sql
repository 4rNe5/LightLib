-- The series a reader makes are one shared setting for the whole library
-- (the books' MD5s under each series' name): past 4096 characters once a
-- hundred books are grouped. The keys stay far below either limit.
alter table public.settings drop constraint settings_value_check;
alter table public.settings
  add constraint settings_value_check check (length(value) <= 262144);
