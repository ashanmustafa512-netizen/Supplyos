-- Add covering indexes for the two nullable auth-user foreign keys used in inspection audit trails.
create index if not exists dispatch_truck_passes_issued_by_idx on public.dispatch_truck_passes(issued_by);
create index if not exists dispatch_truck_passes_checked_by_idx on public.dispatch_truck_passes(checked_by);
