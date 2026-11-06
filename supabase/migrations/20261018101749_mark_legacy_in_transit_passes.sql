-- Existing loads already in motion when inspection gates were introduced must not look pre-cleared.
-- Preserve an auditable gate record without claiming an inspection occurred retroactively.
update public.dispatch_truck_passes p
set status='hold',
    inspection_notes='Historical backfill: this load was already in transit before SupplyOS truck inspection controls were installed. This record does not attest that a pre-departure inspection occurred.',
    inspection_snapshot=jsonb_set(coalesce(p.inspection_snapshot,'{}'::jsonb),'{legacy_backfill}', 'true'::jsonb, true),
    updated_at=now()
from public.dispatch_loads l
where l.id=p.load_id and l.status='in_transit' and p.status='inspection_pending' and p.checked_at is null;
