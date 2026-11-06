import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Activity, ArrowLeft, ArrowRight, CalendarClock, CheckCircle2, Clock3, Construction, MapPinned, Package, ShieldCheck, Truck, Users, Wallet } from "lucide-react";

const moduleInfo: Record<string, { title: string; subtitle: string; icon: typeof Truck; stage: string; intro: string; features: string[]; dependency: string }> = {
  routes: { title: "Route planning & geofencing", subtitle: "Plan routes and create a better view of delivery activity.", icon: MapPinned, stage: "PLANNED", intro: "This module will connect dispatch jobs with route planning, delivery areas, and location-based rules. Live maps and geofencing require a map provider and the factory's delivery requirements.", features: ["Route and stop planning", "Region and delivery-zone configuration", "Geofence events and arrival visibility", "Route performance reports"], dependency: "Requires the dispatch workflow and a configured map provider." },
  accounting: { title: "Accounting", subtitle: "Bring operational costs and business performance into view.", icon: Activity, stage: "PLANNED", intro: "The accounting module will build on booking revenue and product costs. Its ledger, payment, tax, and reconciliation rules should be defined against your factory's accounting practices before posting real transactions.", features: ["Sales and cost summaries", "Payment and expense records", "Account and journal configuration", "Period-based financial reporting"], dependency: "Requires accounting rules and confirmation of your chart of accounts." },
  sales: { title: "Sales & recovery", subtitle: "Track receivables, customer balances, and collections.", icon: Wallet, stage: "PLANNED", intro: "The Sales & Recovery module will connect approved/completed bookings to outstanding customer credit. Credit is currently reserved on approval and remains outstanding after completion until a recovery workflow is built.", features: ["Customer receivables and balance aging", "Collection and payment records", "Credit exposure by customer", "Recovery reports and follow-up queues"], dependency: "Customer credit controls are available; recording and allocating payments is still to be built." },
  payroll: { title: "Payroll", subtitle: "Prepare employee and payroll records in one controlled workspace.", icon: Users, stage: "PLANNED", intro: "Payroll will need employee records, salary components, attendance inputs, approval roles, and local payroll rules before it can calculate real pay runs.", features: ["Employee directory and payroll profiles", "Salary components and allowances", "Payroll review and approval workflow", "Payslip and period reports"], dependency: "Requires your payroll policy, employee data model, and local statutory requirements." },
};

export async function generateMetadata({ params }: { params: Promise<{ module: string }> }): Promise<Metadata> {
  const { module } = await params;
  return { title: moduleInfo[module]?.title ?? "Module" };
}

export default async function PlannedModulePage({ params }: { params: Promise<{ module: string }> }) {
  const { module } = await params;
  const info = moduleInfo[module];
  if (!info) notFound();
  const Icon = info.icon;
  return <div className="page-stack module-roadmap-page">
    <Link href="/dashboard" className="back-link"><ArrowLeft size={16}/> Back to all modules</Link>
    <div className="roadmap-hero"><div className="roadmap-icon"><Icon size={26}/></div><span className="roadmap-stage"><Construction size={14}/>{info.stage}</span><h1>{info.title}</h1><p>{info.subtitle}</p><div className="roadmap-progress"><div><span>Module build status</span><strong>{module === "dispatch" ? "Foundation" : "Not yet implemented"}</strong></div><div className="roadmap-progress-track"><i style={{ width: module === "dispatch" ? "24%" : "8%" }}/></div></div></div>
    <div className="roadmap-content-grid"><section className="panel roadmap-description"><div className="panel-heading"><div><h2>Module scope</h2><p>Planned product behavior</p></div><span className="panel-heading-icon"><Icon size={17}/></span></div><p>{info.intro}</p><div className="roadmap-feature-list">{info.features.map((feature, index) => <div className="roadmap-feature" key={feature}><span>{String(index + 1).padStart(2, "0")}</span><strong>{feature}</strong><Clock3 size={15}/></div>)}</div></section><aside className="panel roadmap-next"><div className="panel-heading"><div><h2>Build dependencies</h2><p>Before this module goes live</p></div></div><div className="dependency-status"><CheckCircle2 size={17}/><span>{info.dependency}</span></div><div className="dependency-status dependency-muted"><CalendarClock size={17}/><span>UI and data workflow for this module are not yet implemented.</span></div><div className="roadmap-note"><ShieldCheck size={16}/><p>This placeholder is intentional. It will not generate fake records or claim that workflows are operational.</p></div><Link href={module === "dispatch" ? "/bookings" : "/dashboard"} className="button button-secondary button-full">{module === "dispatch" ? "Review approved booking source" : "Return to workspace"}<ArrowRight size={15}/></Link></aside></div>
    <div className="notice notice-info"><Package size={16}/> <span><strong>What works today:</strong> protected login, workspace isolation, customer and product records, booking creation, database-backed approvals, credit limits, stock reservation, cancellation, and completion updates.</span></div>
  </div>;
}
