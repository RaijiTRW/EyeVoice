insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'eyevoice-releases',
  'eyevoice-releases',
  true,
  536870912,
  array['application/x-apple-diskimage', 'application/xml', 'text/xml', 'text/markdown', 'text/plain']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Public read EyeVoice releases" on storage.objects;
create policy "Public read EyeVoice releases"
on storage.objects
for select
to public
using (bucket_id = 'eyevoice-releases');
