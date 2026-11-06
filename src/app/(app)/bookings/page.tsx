import type { Metadata } from "next";
import Link from "next/link";
import { CheckCircle2, Coins, Percent, Plus, SlidersHorizontal, TrendingDown } from "lucide-react";
import { BookingExplorer, type BookingRow } from "@/components/booking-explorer";
import { requireUser } from "@/lib/server-auth";
import { money } from "@/lib/format";

export const metadata: Metadata = { title: "Bookings" };

type SearchParams = Promise<{ success?: string; error?: string }>;

export default async function BookingsPage({ searchParams }: { searchParams: SearchParams }) {
  const params = await searchParams;
  const { supabase } = await requireUser();
  const { data, error } = await supabase
    .from("bookings")
    .select("id, booking_no, booking_date, status, total_amount, total_cost, profit, score_snapshot, city, region, notes, created_at, customers(name, customer_code), booking_items(quantity, products(name, sku))")
    .order("created_at", { ascending: false })
    .limit(500);

  const bookings = (data ?? []) as unknown as BookingRow[];
  const monthParts = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Karachi", year: "numeric", month: "2-digit" }).formatToParts(new Date());
  const year = monthParts.find(part => part.type === "year")?.value ?? "2026";
  const month = monthParts.find(part => part.type === "month")?.value ?? "01";
  const monthStart = `${year}-${month}-01`;
  const { data: monthData } = await supabase.from("bookings").select("status, total_amount").gte("booking_date", monthStart);
  const monthRows = monthData ?? [];
  const approvedRows = monthRows.filter(row => row.status === "approved" || row.status === "completed");
  const cancelledRows = monthRows.filter(row => row.status === "cancelled");
  const approvalRate = monthRows.length ? Math.round(approvedRows.length / monthRows.length * 100) : 0;
  const averageOrder = monthRows.length ? monthRows.reduce((sum, row) => sum + Number(row.total_amount ?? 0), 0) / monthRows.length : 0;
  const approvedValue = approvedRows.reduce((sum, row) => sum + Number(row.total_amount ?? 0), 0);
  const cancelledValue = cancelledRows.reduce((sum, row) => sum + Number(row.total_amount ?? 0), 0);
  return (
    <div className="page-stack">
      <div className="page-heading-row"><div><div className="eyebrow">ORDER MANAGEMENT</div><h1>Bookings <span className="heading-count">{bookings.length}</span></h1><p>Review customer orders, protect inventory, and keep approvals moving.</p></div><div className="heading-actions"><Link href="/bookings/new" className="button button-primary"><Plus size={17}/> Create booking</Link></div></div>
      {params.success && <div className="notice notice-success">{params.success}</div>}
      {params.error && <div className="notice notice-error">{params.error}</div>}
      {error && <div className="notice notice-error">Bookings could not be loaded: {error.message}</div>}
      <div className="metric-grid metric-grid-four booking-analytics-grid">
        <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-green"><Percent size={17}/></span><span className="metric-trend">This month</span></div><div className="metric-value">{approvalRate}<span className="metric-suffix">%</span></div><div className="metric-label">Approval rate</div></div>
        <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-blue"><Coins size={17}/></span><span className="metric-trend">This month</span></div><div className="metric-value metric-value-small">{money(averageOrder)}</div><div className="metric-label">Average order value</div></div>
        <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-violet"><CheckCircle2 size={17}/></span><span className="metric-trend">This month</span></div><div className="metric-value metric-value-small">{money(approvedValue)}</div><div className="metric-label">Approved / completed value</div></div>
        <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-red"><TrendingDown size={17}/></span><span className="metric-trend">This month</span></div><div className="metric-value metric-value-small">{money(cancelledValue)}</div><div className="metric-label">Cancelled order value</div></div>
      </div>
      <BookingExplorer bookings={bookings}/>
      <p className="helper-line"><SlidersHorizontal size={14}/> Credit and stock validations run when an order is approved. Showing the most recent {bookings.length} bookings.</p>
    </div>
  );
}
