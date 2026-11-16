import type { Metadata } from "next";
import Link from "next/link";
import {
  ArrowRight, ArrowUpRight, Boxes, BriefcaseBusiness, Calculator, CheckCircle2,
  ClipboardCheck, Clock3, CreditCard, Factory, MapPinned, PackageCheck, Plus,
  ShieldAlert, Truck, Users, Wallet, Warehouse,
} from "lucide-react";
import { getWorkspace, requireUser } from "@/lib/server-auth";
import { normalizeRole } from "@/lib/access";
import { redirect } from "next/navigation";
import { money } from "@/lib/format";

export const metadata: Metadata = { title: "Overview" };

const modules = [
  { title: "Bookings", description: "Orders, approvals, and credit checks", href: "/bookings", icon: ClipboardCheck, color: "module-blue", tag: "ACTIVE", active: true },
  { title: "Team live location", description: "See active employee and manager shifts", href: "/team-location", icon: MapPinned, color: "module-purple", tag: "ACTIVE", active: true },
  { title: "Procurement, stock & warehouse", description: "Manage product masters and stock", href: "/inventory", icon: Warehouse, color: "module-green", tag: "PARTIAL", active: true },
  { title: "Accounting", description: "Track company expenses, income and profit", href: "/accounting", icon: Calculator, color: "module-teal", tag: "ACTIVE", active: true },
  { title: "Sales & recovery", description: "Track sales, collections and outstanding balances", href: "/sales", icon: CreditCard, color: "module-pink", tag: "ACTIVE", active: true },
  { title: "Payroll", description: "Manage salaries, allowances and payroll cycles", href: "/payroll", icon: Wallet, color: "module-indigo", tag: "ACTIVE", active: true },
];

function startOfMonth() { const today = localDate(); return `${today.slice(0, 7)}-01`; }
function localDate(date = new Date()) { return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Karachi", year: "numeric", month: "2-digit", day: "2-digit" }).format(date); }

export default async function DashboardPage() {
  const { supabase, user } = await requireUser();
  const { organization, membership } = await getWorkspace(supabase, user.id);
  if (!organization || !membership) redirect("/login");
  const role = normalizeRole(membership.role);

  if (role === "staff") {
    const { data: myBookings } = await supabase.from("bookings")
      .select("id,booking_no,status,total_amount,booking_date,customers(name)")
      .order("created_at", { ascending: false }).limit(8);
    const rows = myBookings ?? [];
    const pending = rows.filter(row => row.status === "pending_approval").length;
    const approved = rows.filter(row => row.status === "approved" || row.status === "completed").length;
    return <div className="page-stack dashboard-stack">
      <div className="welcome-heading"><div><div className="eyebrow">EMPLOYEE WORKSPACE</div><h1>Your workday at a glance<span className="heading-period">.</span></h1><p>Create shop orders and follow every booking you have submitted.</p></div></div>
      <div className="overview-hero"><div className="overview-hero-copy"><div className="hero-pill"><span/> EMPLOYEE APP</div><h2>Visit shops.<br/><em>Record orders accurately.</em></h2><p>Start a booking while you are with a shop. Your order will be sent to the owner for approval.</p><div className="hero-actions"><Link href="/bookings/new" className="button button-white"><Plus size={16}/> Create a booking</Link><Link href="/bookings" className="hero-text-link">My bookings <ArrowRight size={15}/></Link></div></div></div>
      <div className="metric-grid metric-grid-three">
        <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-blue"><ClipboardCheck size={17}/></span><span className="metric-trend">Orders</span></div><div className="metric-value">{rows.length}</div><div className="metric-label">Recent bookings</div></div>
        <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-amber"><Clock3 size={17}/></span><span className="metric-trend">Awaiting owner</span></div><div className="metric-value">{pending}</div><div className="metric-label">Pending approval</div></div>
        <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-green"><CheckCircle2 size={17}/></span><span className="metric-trend">Progress</span></div><div className="metric-value">{approved}</div><div className="metric-label">Approved or completed</div></div>
      </div>
      <section className="panel recent-panel"><div className="panel-heading"><div><h2>Your recent bookings</h2><p>Only bookings submitted by your account are shown here.</p></div><Link className="inline-link" href="/bookings">View all <ArrowRight size={14}/></Link></div><div className="recent-list">{rows.map(row => <Link className="recent-row" href={`/bookings/${row.id}`} key={row.id}><span className="recent-icon"><ClipboardCheck size={17}/></span><span className="recent-copy"><strong>{row.booking_no}</strong><small>{row.customers?.[0]?.name ?? "Shop"} · {row.booking_date}</small></span><span className="recent-amount"><span className={`status-text status-text-${row.status}`}>{row.status.replaceAll("_"," ")}</span></span><ArrowRight size={15}/></Link>)}{!rows.length && <div className="empty-inline"><span><ClipboardCheck size={18}/></span><div><strong>No bookings yet</strong><p>Create your first shop order to get started.</p></div><Link href="/bookings/new" className="button button-small button-primary">Create booking</Link></div>}</div></section>
    </div>;
  }

  if (role === "manager") {
    const [recentResult, pendingResult, productResult] = await Promise.all([
      supabase.from("bookings").select("id,booking_no,status,booking_date,customers(name)").order("created_at", { ascending: false }).limit(6),
      supabase.from("bookings").select("id", { count: "exact", head: true }).eq("status", "pending_approval"),
      supabase.from("products").select("id,name,sku,stock_on_hand,stock_reserved").eq("is_active", true).order("name").limit(500),
    ]);
    const recent = recentResult.data ?? [];
    const lowStock = (productResult.data ?? []).filter(product => Number(product.stock_on_hand) - Number(product.stock_reserved) <= 0);
    return <div className="page-stack dashboard-stack">
      <div className="welcome-heading"><div><div className="eyebrow">MANAGER WORKSPACE</div><h1>Factory operations<span className="heading-period">.</span></h1><p>Keep bookings moving, watch stock levels and coordinate today's work.</p></div></div>
      <div className="overview-hero"><div className="overview-hero-copy"><div className="hero-pill"><span/> MANAGER APP</div><h2>Keep the factory moving.<br/><em>One clear operating view.</em></h2><p>Create orders from shop visits, monitor inventory and follow pending owner approvals.</p><div className="hero-actions"><Link href="/bookings/new" className="button button-white"><Plus size={16}/> Create booking</Link><Link href="/inventory" className="hero-text-link">Open stock <ArrowRight size={15}/></Link></div></div></div>
      <div className="metric-grid metric-grid-three">
        <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-blue"><ClipboardCheck size={17}/></span><span className="metric-trend">Bookings</span></div><div className="metric-value">{recent.length}</div><div className="metric-label">Recent orders loaded</div></div>
        <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-amber"><Clock3 size={17}/></span><span className="metric-trend">Owner review</span></div><div className="metric-value">{pendingResult.count ?? 0}</div><div className="metric-label">Pending approvals</div></div>
        <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-rose"><ShieldAlert size={17}/></span><span className="metric-trend">Stock alert</span></div><div className="metric-value">{lowStock.length}</div><div className="metric-label">Products with no available stock</div></div>
      </div>
      <div className="module-grid">
        <Link href="/bookings" className="module-card module-card-active"><div className="module-card-top"><span className="module-icon module-blue"><ClipboardCheck size={19}/></span><span className="module-tag module-tag-active">ACTIVE</span></div><h3>Bookings</h3><p>Create shop orders and monitor their approval status.</p><div className="module-card-bottom"><span>Open bookings</span><span className="module-arrow"><ArrowRight size={16}/></span></div></Link>
        <Link href="/inventory" className="module-card module-card-active"><div className="module-card-top"><span className="module-icon module-green"><Warehouse size={19}/></span><span className="module-tag module-tag-active">ACTIVE</span></div><h3>Stock & warehouse</h3><p>Review stock levels and record permitted warehouse activity.</p><div className="module-card-bottom"><span>Open inventory</span><span className="module-arrow"><ArrowRight size={16}/></span></div></Link>
        <Link href="/sales" className="module-card module-card-active"><div className="module-card-top"><span className="module-icon module-pink"><CreditCard size={19}/></span><span className="module-tag module-tag-active">ACTIVE</span></div><h3>Sales & recovery</h3><p>Follow invoices, receipts and assigned recovery work.</p><div className="module-card-bottom"><span>Open sales</span><span className="module-arrow"><ArrowRight size={16}/></span></div></Link>
      </div>
      <section className="panel recent-panel"><div className="panel-heading"><div><h2>Recent bookings</h2><p>Company-wide order activity.</p></div><Link className="inline-link" href="/bookings">View all <ArrowRight size={14}/></Link></div><div className="recent-list">{recent.map(row => <Link className="recent-row" href={`/bookings/${row.id}`} key={row.id}><span className="recent-icon"><ClipboardCheck size={17}/></span><span className="recent-copy"><strong>{row.booking_no}</strong><small>{row.customers?.[0]?.name ?? "Shop"} · {row.booking_date}</small></span><span className={`status-text status-text-${row.status}`}>{row.status.replaceAll("_"," ")}</span><ArrowRight size={15}/></Link>)}</div></section>
    </div>;
  }

  if (!["owner", "admin"].includes(role)) {
    return <div className="page-stack"><h1>Workspace access</h1><p>Your assigned role does not have access to the Owner, Manager, or Employee app features.</p></div>;
  }

  const today = localDate();
  const [summaryResult, { data: recentBookings }] = await Promise.all([
    supabase.rpc("supplyos_dashboard_summary", { p_month_start: startOfMonth(), p_today: today }),
    supabase.from("bookings").select("id, booking_no, status, total_amount, booking_date, city, customers(name)").order("created_at", { ascending: false }).limit(6),
  ]);

  // The RPC aggregates records in Postgres so the dashboard does not download
  // hundreds or thousands of rows just to calculate summary cards and charts.
  type DashboardSummary = {
    order_count?: number; approved_count?: number; cancelled_count?: number;
    approved_value?: number | string; cancelled_value?: number | string;
    today_count?: number; pending_count?: number; customer_count?: number;
    low_stock_count?: number;
    daily_counts?: Array<{ booking_date: string; count: number }>;
    low_stock_products?: Array<{ id: string; name: string; sku: string; stock_on_hand: number | string; stock_reserved: number | string }>;
  };
  let summary = (summaryResult.data ?? null) as DashboardSummary | null;
  // Keep the page usable before the new migration is applied. This fallback is
  // intentionally narrow; the RPC path above is the normal production path.
  if (summaryResult.error || !summary) {
    const [{ data: rows }, { count: fallbackPending }, { count: fallbackCustomers }, { data: productRows }] = await Promise.all([
      supabase.from("bookings").select("booking_date, status, total_amount").gte("booking_date", startOfMonth()).limit(1500),
      supabase.from("bookings").select("id", { count: "exact", head: true }).eq("status", "pending_approval"),
      supabase.from("customers").select("id", { count: "exact", head: true }).eq("status", "active"),
      supabase.from("products").select("id, name, sku, stock_on_hand, stock_reserved").eq("is_active", true).order("name").limit(500),
    ]);
    const fallbackRows = rows ?? [];
    const dayCounts = new Map<string, number>();
    for (const row of fallbackRows) dayCounts.set(row.booking_date, (dayCounts.get(row.booking_date) ?? 0) + 1);
    const fallbackLowStock = (productRows ?? []).filter(product => Number(product.stock_on_hand) - Number(product.stock_reserved) <= 0);
    const approvedRows = fallbackRows.filter(row => row.status === "approved" || row.status === "completed");
    const cancelledRows = fallbackRows.filter(row => row.status === "cancelled");
    summary = {
      order_count: fallbackRows.length,
      approved_count: approvedRows.length,
      cancelled_count: cancelledRows.length,
      approved_value: approvedRows.reduce((total, row) => total + Number(row.total_amount ?? 0), 0),
      cancelled_value: cancelledRows.reduce((total, row) => total + Number(row.total_amount ?? 0), 0),
      today_count: fallbackRows.filter(row => row.booking_date === today).length,
      pending_count: fallbackPending ?? 0,
      customer_count: fallbackCustomers ?? 0,
      low_stock_count: fallbackLowStock.length,
      low_stock_products: fallbackLowStock.slice(0, 3),
      daily_counts: [...dayCounts].map(([booking_date, count]) => ({ booking_date, count })),
    };
  }
  const recent = recentBookings ?? [];
  const orderCount = Number(summary.order_count ?? 0);
  const approvedCount = Number(summary.approved_count ?? 0);
  const pendingCount = Number(summary.pending_count ?? 0);
  const customerCount = Number(summary.customer_count ?? 0);
  const approvedValue = Number(summary.approved_value ?? 0);
  const cancelledValue = Number(summary.cancelled_value ?? 0);
  const approvalRate = orderCount ? Math.round((approvedCount / orderCount) * 100) : 0;
  const dailyByDate = new Map<string, number>((summary.daily_counts ?? []).map(row => [row.booking_date, Number(row.count)] as const));
  const daily = Array.from({ length: new Date().getDate() }, (_, index) => {
    const date = `${today.slice(0, 8)}${String(index + 1).padStart(2, "0")}`;
    return { day: index + 1, count: dailyByDate.get(date) ?? 0 };
  });
  const maxDaily = Math.max(1, ...daily.map(d => d.count));
  const lowStock = summary.low_stock_products ?? [];
  const lowStockCount = Number(summary.low_stock_count ?? lowStock.length);
  const actionCount = pendingCount + lowStockCount;

  return <div className="page-stack dashboard-stack">
    <div className="welcome-heading"><div><div className="eyebrow">{new Intl.DateTimeFormat("en-PK", { weekday: "long", timeZone: "Asia/Karachi" }).format(new Date()).toUpperCase()} · OPERATIONS AT A GLANCE</div><h1>Good work starts with a clear view<span className="heading-period">.</span></h1><p>Here is what is moving across your factory today.</p></div><div className="welcome-date"><span className="welcome-date-day">{new Intl.DateTimeFormat("en-PK", { day: "2-digit", timeZone: "Asia/Karachi" }).format(new Date())}</span><span><strong>{new Intl.DateTimeFormat("en-PK", { month: "long", timeZone: "Asia/Karachi" }).format(new Date())}</strong><small>{new Intl.DateTimeFormat("en-PK", { weekday: "long", year: "numeric", timeZone: "Asia/Karachi" }).format(new Date())}</small></span></div></div>
    <div className="overview-hero"><div className="overview-hero-copy"><div className="hero-pill"><span/> LIVE WORKSPACE</div><h2>One connected view.<br/><em>Better decisions, every day.</em></h2><p>Keep bookings, customer credit, and available stock working in sync — without hopping between spreadsheets.</p><div className="hero-actions"><Link href="/bookings/new" className="button button-white"><Plus size={16}/> Create a booking</Link><Link href="/bookings" className="hero-text-link">Open order pipeline <ArrowRight size={15}/></Link></div></div><div className="hero-illustration" aria-hidden="true"><div className="hero-orbit orbit-one"/><div className="hero-orbit orbit-two"/><div className="hero-factory-card"><div className="hero-factory-head"><span><Factory size={16}/></span><div><strong>Factory overview</strong><small>Unified operations</small></div><i/></div><div className="hero-mini-graph"><i style={{height:"36%"}}/><i style={{height:"52%"}}/><i style={{height:"45%"}}/><i style={{height:"74%"}}/><i style={{height:"60%"}}/><i style={{height:"88%"}}/><i style={{height:"68%"}}/><i style={{height:"100%"}}/></div><div className="hero-mini-footer"><span><b/> Bookings syncing</span><span>+ inventory</span></div></div><div className="floating-chip chip-approved"><CheckCircle2 size={15}/><span><strong>{approvedCount}</strong><small>approved this month</small></span></div><div className="floating-chip chip-orders"><PackageCheck size={15}/><span><strong>{pendingCount}</strong><small>awaiting review</small></span></div></div><div className="hero-decoration hero-decoration-a"/><div className="hero-decoration hero-decoration-b"/></div>

    <div className="section-heading-row"><div><div className="eyebrow">THIS MONTH</div><h2>Operational performance</h2></div><span className="data-refresh"><span className="health-dot"/> Connected to your database</span></div>
    <div className="metric-grid metric-grid-four">
      <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-blue"><ClipboardCheck size={17}/></span><span className="metric-trend">Bookings</span></div><div className="metric-value">{Number(summary.today_count ?? 0)}<small className="metric-unit">today</small></div><div className="metric-label">Bookings created today</div><div className="metric-card-bottom"><span>All statuses</span><Link href="/bookings">View orders <ArrowUpRight size={13}/></Link></div></div>
      <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-amber"><Clock3 size={17}/></span><span className="metric-trend metric-trend-warn">Needs attention</span></div><div className="metric-value">{pendingCount}</div><div className="metric-label">Pending approvals</div><div className="metric-card-bottom"><span>Awaiting a decision</span><Link href="/bookings">Review queue <ArrowUpRight size={13}/></Link></div></div>
      <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-green"><CheckCircle2 size={17}/></span><span className="metric-trend">Approval rate</span></div><div className="metric-value">{approvalRate}<span className="metric-suffix">%</span></div><div className="metric-label">Approved or completed</div><div className="metric-card-bottom"><span>From {orderCount} this-month orders</span><span className="micro-positive">{approvedCount} approved</span></div></div>
      <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-violet"><Users size={17}/></span><span className="metric-trend">Customer base</span></div><div className="metric-value">{customerCount}</div><div className="metric-label">Active customer accounts</div><div className="metric-card-bottom"><span>Credit controls</span><Link href="/customers">Manage customers <ArrowUpRight size={13}/></Link></div></div>
    </div>

    <div className="analytics-grid"><section className="panel trend-panel"><div className="panel-heading"><div><h2>Daily booking trend</h2><p>Number of bookings recorded each day this month.</p></div><span className="chart-total"><strong>{orderCount}</strong><small>this month</small></span></div><div className="bar-chart" role="img" aria-label="Daily booking volume for the current month">{daily.map((entry) => <div className="bar-column" key={entry.day}><div className="bar-value-space"><span className={`bar-fill ${entry.day === Number(today.slice(8,10)) ? "bar-fill-today" : ""}`} style={{height: `${Math.max(entry.count ? 6 : 2, entry.count / maxDaily * 100)}%`}} title={`${entry.count} bookings`}/></div><span className={`bar-label ${entry.day % 3 === 1 || entry.day === daily.length ? "bar-label-visible" : ""}`}>{entry.day}</span></div>)}</div><div className="chart-legend"><span><i className="legend-dot legend-blue"/> Bookings per day</span><span><i className="legend-dot legend-dark"/> Current day</span></div></section>
      <section className="panel action-panel"><div className="panel-heading"><div><h2>Action required</h2><p>Items that may need a follow-up.</p></div><span className={`action-count ${actionCount ? "action-count-warn" : ""}`}>{actionCount}</span></div>{pendingCount > 0 && <Link href="/bookings" className="action-item"><span className="action-item-icon action-item-amber"><Clock3 size={16}/></span><span className="action-item-copy"><strong>{pendingCount} booking{pendingCount === 1 ? "" : "s"} awaiting approval</strong><small>Check available stock and customer credit.</small></span><ArrowRight size={16}/></Link>}{lowStock.slice(0, 3).map(p => <Link href="/inventory" className="action-item" key={p.id}><span className="action-item-icon action-item-rose"><ShieldAlert size={16}/></span><span className="action-item-copy"><strong>{p.name} has no available stock</strong><small>{p.sku} · {p.stock_reserved} reserved of {p.stock_on_hand}</small></span><ArrowRight size={16}/></Link>)}{actionCount === 0 && <div className="all-clear"><span><CheckCircle2 size={20}/></span><strong>You’re all caught up</strong><p>No pending approvals or zero-availability products detected.</p></div>}<div className="action-panel-footer"><span>Automatically based on current records</span><Link href="/bookings">Open queue <ArrowRight size={13}/></Link></div></section></div>

    <div className="section-heading-row module-section-heading"><div><div className="eyebrow">YOUR WORKSPACE</div><h2>Operations modules</h2><p>Open a module to work with its dedicated tools and records.</p></div><span className="module-count-label">7 MODULES</span></div>
    <div className="module-grid">{modules.map((module, index) => { const Icon = module.icon; return <Link href={module.href} key={module.href} className={`module-card ${module.active ? "module-card-active" : "module-card-planned"}`}><div className="module-card-top"><span className={`module-icon ${module.color}`}><Icon size={19}/></span><span className={`module-tag ${module.active ? "module-tag-active" : ""}`}>{module.active && <i/>}{module.tag}</span></div><h3>{module.title}</h3><p>{module.description}</p><div className="module-card-bottom"><span>{module.active ? "Open module" : "View roadmap"}</span><span className="module-arrow"><ArrowRight size={16}/></span></div><span className="module-card-number">0{index + 1}</span></Link>; })}</div>

    <div className="bottom-summary-grid"><section className="panel recent-panel"><div className="panel-heading"><div><h2>Recent bookings</h2><p>Most recent updates in your order pipeline.</p></div><Link className="inline-link" href="/bookings">View all <ArrowRight size={14}/></Link></div><div className="recent-list">{recent.map(b => <Link className="recent-row" href="/bookings" key={b.id}><span className="recent-icon"><ClipboardCheck size={17}/></span><span className="recent-copy"><strong>{b.booking_no}</strong><small>{b.customers?.[0]?.name ?? "Customer"} · {b.city || "No city"}</small></span><span className="recent-amount"><strong>{money(Number(b.total_amount ?? 0))}</strong><span className={`status-text status-text-${b.status}`}>{({pending_approval:"Pending approval",approved:"Approved",cancelled:"Cancelled",rejected:"Rejected",completed:"Completed",remade:"Remade"} as Record<string,string>)[b.status] ?? b.status}</span></span><ArrowRight size={15} className="recent-arrow"/></Link>)}{!recent.length && <div className="empty-inline"><span><ClipboardCheck size={18}/></span><div><strong>No bookings yet</strong><p>Once you create your first booking, it will appear here.</p></div><Link href="/bookings/new" className="button button-small button-primary">Create booking</Link></div>}</div></section><section className="panel quick-panel"><div className="panel-heading"><div><h2>Quick actions</h2><p>Shortcuts for daily operations.</p></div><span className="panel-heading-icon"><BriefcaseBusiness size={17}/></span></div><div className="quick-action-list"><Link href="/bookings/new" className="quick-action"><span className="quick-action-icon quick-blue"><Plus size={18}/></span><span><strong>Create a booking</strong><small>Enter a new customer order</small></span><ArrowRight size={15}/></Link><Link href="/team-location" className="quick-action"><span className="quick-action-icon quick-violet"><MapPinned size={18}/></span><span><strong>View team locations</strong><small>See active manager and employee shifts</small></span><ArrowRight size={15}/></Link><Link href="/inventory" className="quick-action"><span className="quick-action-icon quick-green"><Boxes size={18}/></span><span><strong>Update inventory</strong><small>Product stock, cost, and pricing</small></span><ArrowRight size={15}/></Link><div className="quick-action quick-action-static"><span className="quick-action-icon quick-orange"><BarChartPlaceholder/></span><span><strong>Monthly approved value</strong><small>{money(approvedValue)} approved or completed</small></span><span className="quick-value">{cancelledValue ? `${money(cancelledValue)} cancelled` : "No cancellations"}</span></div></div></section></div>
  </div>;
}

function BarChartPlaceholder() { return <Factory size={18}/>; }
