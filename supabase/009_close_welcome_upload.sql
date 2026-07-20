-- Run after both welcome assets have been uploaded.
drop policy if exists "temporary-paper-flight-welcome-upload" on storage.objects;
