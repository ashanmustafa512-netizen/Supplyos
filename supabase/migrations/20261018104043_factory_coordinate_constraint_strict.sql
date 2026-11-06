-- Enforce either a fully configured factory point or no coordinates at all.
alter table public.organizations drop constraint if exists organizations_factory_coordinates_check;
alter table public.organizations add constraint organizations_factory_coordinates_check
  check (
    (factory_latitude is null and factory_longitude is null)
    or
    (factory_latitude is not null and factory_longitude is not null
     and factory_latitude between -90 and 90
     and factory_longitude between -180 and 180)
  );
