"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { ArrowRight, Check, CircleX, Clock3, Eye, MoreHorizontal, PackageCheck, Search, ShieldCheck, RefreshCw } from "lucide-react";
import { bookingAction, bulkApproveBookingsInline } from "@/app/(app)/bookings/actions";
import { money } from "@/lib/format";

export type BookingRow = {
  id: string;
  booking_no: string;
  booking_date: string;
  status: string;
  total_amount: number | string;
  total_cost: number | string;
  profit: number | string;
  score_snapshot: number;
  city: string;
  region: string;
  notes: string;
  created_at: string;
  customers: { name: string; customer_code: string } | null;
  booking_items: { quantity: number | string; products: { name: string; sku: string } | null }[];
};

const statusTabs = [
  { key: "all", label: "All bookings" },
  { key: "pending_approval", label: "Pending approvals" },
  { key: "approved", label: "Approved" },
  { key: "cancelled", label: "Cancelled" },
  { key: "rejected", label: "Rejected" },
  { key: "completed", label: "Completed" },
  { key: "remade", label: "Remade" },
];
const statusLabels: Record<string, string> = { pending_approval: "Pending approval", approved: "Approved", cancelled: "Cancelled", rejected: "Rejected", completed: "Completed", remade: "Remade" };

export function BookingExplorer({ bookings }: { bookings: BookingRow[] }) {
  const [rows, setRows] = useState(bookings);
  const [bulkBusy, setBulkBusy] = useState(false);
  const [bulkNotice, setBulkNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [status, setStatus] = useState("pending_approval");
  const [search, setSearch] = useState("");
  const [region, setRegion] = useState("all");
  const [city, setCity] = useState("all");
  const [selectedIds, setSelectedIds] = useState<string[]>([]);

  const counts = useMemo(() => Object.fromEntries(statusTabs.map(tab => [
    tab.key,
    tab.key === "all" ? rows.length : rows.filter(booking => booking.status === tab.key).length,
  ])), [rows]);
  const regions = useMemo(() => [...new Set(rows.map(booking => booking.region.trim()).filter(Boolean))].sort((a, b) => a.localeCompare(b)), [rows]);
  const cities = useMemo(() => [...new Set(rows
    .filter(booking => region === "all" || booking.region.trim() === region)
    .map(booking => booking.city.trim())
    .filter(Boolean))].sort((a, b) => a.localeCompare(b)), [rows, region]);
  const filtered = useMemo(() => rows.filter(booking => {
    const matchesStatus = status === "all" || booking.status === status;
    const haystack = [booking.booking_no, booking.customers?.name, booking.customers?.customer_code, booking.city, booking.region, ...booking.booking_items.map(item => item.products?.name)].join(" ").toLowerCase();
    return matchesStatus
      && haystack.includes(search.toLowerCase().trim())
      && (region === "all" || booking.region.trim() === region)
      && (city === "all" || booking.city.trim() === city);
  }), [rows, city, region, search, status]);

  const visiblePending = filtered.filter(booking => booking.status === "pending_approval");
  const visiblePendingIds = visiblePending.map(booking => booking.id);
  const bulkEligibleIds = visiblePendingIds.slice(0, 100);
  const allVisibleSelected = bulkEligibleIds.length > 0 && bulkEligibleIds.every(id => selectedIds.includes(id));
  const selectedVisibleCount = visiblePendingIds.filter(id => selectedIds.includes(id)).length;
  const setFiltersChanged = () => setSelectedIds([]);

  function toggleSelected(id: string, checked: boolean) {
    setSelectedIds(current => checked ? [...new Set([...current, id])] : current.filter(selectedId => selectedId !== id));
  }

  function toggleVisiblePending(checked: boolean) {
    setSelectedIds(current => {
      if (checked) return [...new Set([...current.filter(id => !visiblePendingIds.includes(id)), ...bulkEligibleIds])].slice(0, 100);
      return current.filter(id => !bulkEligibleIds.includes(id));
    });
  }

  return (
    <div className="booking-explorer">
      <div className="booking-kpis">
        <button type="button" className={`booking-kpi ${status === "pending_approval" ? "booking-kpi-selected" : ""}`} onClick={() => { setFiltersChanged(); setStatus("pending_approval"); }}><span className="kpi-icon kpi-amber"><Clock3 size={17}/></span><span className="booking-kpi-copy"><small>Awaiting review</small><strong>{counts.pending_approval}</strong><em>Need a decision</em></span><ArrowRight size={16} className="kpi-arrow"/></button>
        <button type="button" className={`booking-kpi ${status === "cancelled" ? "booking-kpi-selected" : ""}`} onClick={() => { setFiltersChanged(); setStatus("cancelled"); }}><span className="kpi-icon kpi-rose"><CircleX size={17}/></span><span className="booking-kpi-copy"><small>Cancelled</small><strong>{counts.cancelled}</strong><em>Not proceeding</em></span><ArrowRight size={16} className="kpi-arrow"/></button>
        <button type="button" className={`booking-kpi ${status === "rejected" ? "booking-kpi-selected" : ""}`} onClick={() => { setFiltersChanged(); setStatus("rejected"); }}><span className="kpi-icon kpi-red"><ShieldCheck size={17}/></span><span className="booking-kpi-copy"><small>Rejected</small><strong>{counts.rejected}</strong><em>Declined orders</em></span><ArrowRight size={16} className="kpi-arrow"/></button>
        <button type="button" className={`booking-kpi ${status === "completed" ? "booking-kpi-selected" : ""}`} onClick={() => { setFiltersChanged(); setStatus("completed"); }}><span className="kpi-icon kpi-green"><Check size={17}/></span><span className="booking-kpi-copy"><small>Completed</small><strong>{counts.completed}</strong><em>Fulfilled orders</em></span><ArrowRight size={16} className="kpi-arrow"/></button>
        <button type="button" className={`booking-kpi ${status === "remade" ? "booking-kpi-selected" : ""}`} onClick={() => { setFiltersChanged(); setStatus("remade"); }}><span className="kpi-icon kpi-purple"><RefreshCw size={17}/></span><span className="booking-kpi-copy"><small>Remade</small><strong>{counts.remade}</strong><em>Replacement orders</em></span><ArrowRight size={16} className="kpi-arrow"/></button>
      </div>

      <section className="panel booking-list-panel">
        <div className="panel-heading booking-list-heading"><div><h2>Order pipeline</h2><p>Search by order or customer, filter by destination, then take action.</p></div><span className="table-count">{filtered.length} results</span></div>
        <div className="booking-toolbar booking-toolbar-stack">
          <div className="booking-toolbar-top">
            <div className="search-field"><Search size={16}/><input aria-label="Search bookings" value={search} onChange={event => { setSearch(event.target.value); setFiltersChanged(); }} placeholder="Search booking, customer, city…"/><kbd>Search</kbd></div>
            <div className="booking-toolbar-actions">
              <button className="button button-small button-secondary" onClick={() => { setSearch(""); setStatus("all"); setRegion("all"); setCity("all"); setSelectedIds([]); }} type="button">Clear filters</button>
              <Link className="button button-small button-primary" href="/bookings/new"> <span>Create booking</span></Link>
            </div>
          </div>
          <div className="booking-filter-row">
            <label className="booking-filter"><span>Region</span><select aria-label="Filter by region" value={region} onChange={event => { setRegion(event.target.value); setCity("all"); setFiltersChanged(); }}><option value="all">All regions</option>{regions.map(value => <option value={value} key={value}>{value}</option>)}</select></label>
            <label className="booking-filter"><span>City</span><select aria-label="Filter by city" value={city} onChange={event => { setCity(event.target.value); setFiltersChanged(); }}><option value="all">All cities</option>{cities.map(value => <option value={value} key={value}>{value}</option>)}</select></label>
            <span className="booking-filter-hint">Region and city filters; bulk approval supports up to 100 orders per batch.</span>
          </div>
        </div>

        <div className="status-tabs" role="tablist" aria-label="Filter bookings by status">{statusTabs.map(tab => <button type="button" role="tab" aria-selected={status === tab.key} className={`status-tab ${status === tab.key ? "status-tab-active" : ""}`} key={tab.key} onClick={() => { setFiltersChanged(); setStatus(tab.key); }}>{tab.label}<span>{counts[tab.key] ?? 0}</span></button>)}</div>

        {visiblePending.length > 0 && <div className="bulk-approval-bar">
          <label className="select-visible-pending"><input type="checkbox" checked={allVisibleSelected} onChange={event => toggleVisiblePending(event.target.checked)}/><span>Select up to 100 visible pending</span></label>
          <div className="bulk-approval-copy">{selectedIds.length > 0 ? <span><strong>{selectedIds.length}</strong> selected</span> : <span>Choose pending orders to approve together</span>}
            <form onSubmit={async event => { event.preventDefault(); if (bulkBusy || !selectedIds.length) return; setBulkBusy(true); setBulkNotice(null); const result = await bulkApproveBookingsInline(selectedIds); setBulkBusy(false); if (result.approvedIds.length) { setRows(current => current.map(row => result.approvedIds.includes(row.id) ? { ...row, status: "approved" } : row)); setSelectedIds(current => current.filter(id => !result.approvedIds.includes(id))); } const message = result.approvedIds.length ? `Approved ${result.approvedIds.length} booking${result.approvedIds.length === 1 ? "" : "s"}.` : "No bookings were approved."; setBulkNotice({ ok: result.approvedIds.length > 0 && result.failures.length === 0, text: `${message}${result.failures.length ? ` ${result.failures.length} failed: ${result.failures.slice(0, 2).map(issue => issue.message).join("; ")}` : " Credit and stock checks passed."}` }); }}>
              {selectedIds.map(id => <input type="hidden" name="booking_ids" value={id} key={id}/>)}
              <button className="button button-small button-primary" type="submit" disabled={selectedIds.length === 0 || bulkBusy}>{bulkBusy ? <RefreshCw size={14} className="spin-icon"/> : <Check size={14}/>} {bulkBusy ? "Approving…" : "Approve selected"}{selectedIds.length > 0 ? ` (${selectedIds.length})` : ""}</button>
            </form>
          </div>
        </div>}
        {bulkNotice && <div className={`dispatch-inline-status ${bulkNotice.ok ? "success" : "error"}`} role="status"><span>{bulkNotice.ok ? <Check size={16}/> : <CircleX size={16}/>}</span><span>{bulkNotice.text}</span><button type="button" className="icon-button" aria-label="Dismiss notice" onClick={() => setBulkNotice(null)}><CircleX size={15}/></button></div>}
        {selectedVisibleCount > 0 && <p className="bulk-approval-note"><ShieldCheck size={14}/> Each order is checked against customer credit and available stock. Orders that fail a check remain pending approval.</p>}

        <div className="table-scroll"><table className="data-table"><thead><tr><th className="select-column">Select</th><th>Booking</th><th>Customer / destination</th><th>Order value</th><th>Cost & margin</th><th>Credit score</th><th>Status</th><th>Actions</th></tr></thead><tbody>
          {filtered.map(booking => {
            const amount = Number(booking.total_amount ?? 0);
            const cost = Number(booking.total_cost ?? 0);
            const profit = Number(booking.profit ?? (amount - cost));
            const firstItem = booking.booking_items?.[0];
            return <tr key={booking.id}>
              <td className="select-column">{booking.status === "pending_approval" ? <input type="checkbox" aria-label={`Select ${booking.booking_no} for bulk approval`} checked={selectedIds.includes(booking.id)} disabled={selectedIds.length >= 100 && !selectedIds.includes(booking.id)} onChange={event => toggleSelected(booking.id, event.target.checked)}/> : <span className="not-selectable">—</span>}</td>
              <td><div className="booking-primary"><span className="booking-ref">{booking.booking_no}</span><span className="booking-date">{new Intl.DateTimeFormat("en-PK", { day: "2-digit", month: "short", year: "numeric" }).format(new Date(`${booking.booking_date.slice(0, 10)}T12:00:00`))}</span></div></td>
              <td><div className="customer-primary"><span className="customer-avatar">{(booking.customers?.name?.[0] || "C").toUpperCase()}</span><span><strong>{booking.customers?.name ?? "Unknown customer"}</strong><small>{booking.customers?.customer_code ?? "—"} · {[booking.city, booking.region].filter(Boolean).join(", ") || "No destination"}</small>{firstItem && <small className="item-line">{firstItem.products?.name ?? "Product"} · qty {firstItem.quantity}</small>}</span></div></td>
              <td><span className="money-primary">{money(amount)}</span><small className="table-muted">incl. all listed items</small></td>
              <td><span className="money-primary">{money(cost)}</span><small className={profit >= 0 ? "profit-label" : "loss-label"}>{profit >= 0 ? "+" : ""}{money(profit)} profit</small></td>
              <td><div className="score-wrap"><div className="score-line"><span>{booking.score_snapshot}/100</span><span className="score-track"><i style={{ width: `${Math.min(100, Math.max(0, booking.score_snapshot))}%` }}/></span></div></div></td>
              <td><span className={`status-pill status-${booking.status}`}><i/>{statusLabels[booking.status] ?? booking.status}</span></td>
              <td><div className="row-actions">
                {booking.status === "pending_approval" && <>
                  <form action={bookingAction}><input type="hidden" name="booking_id" value={booking.id}/><input type="hidden" name="action" value="approve"/><button className="action-icon action-approve" title="Approve booking" aria-label={`Approve ${booking.booking_no}`}><Check size={16}/></button></form>
                  <form action={bookingAction}><input type="hidden" name="booking_id" value={booking.id}/><input type="hidden" name="action" value="reject"/><button className="action-icon action-reject" title="Reject booking" aria-label={`Reject ${booking.booking_no}`}><CircleX size={16}/></button></form>
                </>}
                {booking.status === "approved" && <form action={bookingAction}><input type="hidden" name="booking_id" value={booking.id}/><input type="hidden" name="action" value="complete"/><button className="button button-xs button-primary" title="Complete booking"><Check size={13}/> Complete</button></form>}
                {(booking.status === "pending_approval" || booking.status === "approved") && <form action={bookingAction}><input type="hidden" name="booking_id" value={booking.id}/><input type="hidden" name="action" value="cancel"/><button className="action-icon action-more" title="Cancel booking" aria-label={`Cancel ${booking.booking_no}`}><MoreHorizontal size={16}/></button></form>}
                <Link className="action-icon action-more" href={`/bookings/${booking.id}`} title="View booking details" aria-label={`View ${booking.booking_no}`}><Eye size={15}/></Link>
              </div></td>
            </tr>;
          })}
          {filtered.length === 0 && <tr><td colSpan={8}><div className="empty-table"><div className="empty-table-icon"><Search size={20}/></div><strong>{rows.length ? "No bookings match these filters" : "Your booking queue is clear"}</strong><p>{rows.length ? "Try another status, region, city, or search term." : "Create your first booking or add a customer and product before creating an order."}</p>{!rows.length && <Link href="/bookings/new" className="button button-primary button-small">Create first booking</Link>}</div></td></tr>}
        </tbody></table></div>
        <div className="table-footer"><span>Showing {filtered.length} of {rows.length} recent bookings</span><span><i className="legend-dot legend-green"/> Approval checks enabled <ShieldCheck size={14}/></span></div>
      </section>
    </div>
  );
}
