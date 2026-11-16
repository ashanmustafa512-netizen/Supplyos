import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeft, ClipboardCheck, ShieldCheck } from "lucide-react";
import { createBooking } from "@/app/(app)/bookings/actions";
import { requireWorkspaceRole } from "@/lib/server-auth";
import { money } from "@/lib/format";

export const metadata: Metadata = { title: "Create booking" };

type Params = Promise<{ success?: string; error?: string }>;

export default async function NewBookingPage({ searchParams }: { searchParams: Params }) {
  const params = await searchParams;
  const { supabase, membership } = await requireWorkspaceRole(["owner", "admin", "manager", "staff"]);
  const { data: catalogData, error: catalogError } = await supabase.rpc("get_booking_catalog");
  const catalog = (catalogData ?? { shops: [], products: [] }) as unknown as {
    shops: { id: string; customer_code: string; name: string; city: string | null; region: string | null }[];
    products: { id: string; sku: string; name: string; unit: string; unit_price: number | string; stock_on_hand: number | string; stock_reserved: number | string }[];
  };
  const customers = catalog.shops ?? [];
  const products = catalog.products ?? [];
  const isEmployee = membership.role === "staff";
  return (
    <div className="page-stack narrow-page">
      <Link href="/bookings" className="back-link"><ArrowLeft size={16}/> Back to bookings</Link>
      <div className="page-heading-row"><div><div className="eyebrow">ORDER MANAGEMENT / NEW</div><h1>Create a booking</h1><p>Enter a customer order. It will enter the approval queue until approved.</p></div><span className="draft-label"><i/> New booking</span></div>
      {params.success && <div className="notice notice-success">{params.success}</div>}
      {params.error && <div className="notice notice-error">{params.error}</div>}
      {catalogError && <div className="notice notice-error">Booking catalogue could not be loaded: {catalogError.message}</div>}
      {!isEmployee && <div className="heading-actions"><Link href="/bookings/new-shop" className="button button-secondary"><ClipboardCheck size={16}/> Add shop</Link></div>}
      {(!customers.length || !products.length) ? <section className="panel onboarding-panel"><div className="onboarding-icon"><ClipboardCheck size={22}/></div><h2>Set up the basics first</h2><p>Bookings need an existing shop and product. Ask the owner or manager to add missing records before submitting an order.</p><div className="onboarding-links">{!customers.length && (isEmployee ? <span className="muted">Ask the owner or manager to add a shop first.</span> : <Link href="/bookings/new-shop" className="button button-primary">Add shop</Link>)}{!products.length && (isEmployee ? <span className="muted">Ask the owner or manager to add a product first.</span> : <Link href="/inventory" className="button button-primary">Add a product</Link>)}</div></section> : <form action={createBooking} className="panel booking-create-form">
        <div className="form-section-heading"><div><span className="form-section-number">01</span><div><h2>Customer & delivery</h2><p>Choose the account receiving this order.</p></div></div></div>
        <div className="form-grid"><label className="field-label span-2">Customer account<select name="customer_id" required defaultValue=""><option value="" disabled>Select a customer…</option>{customers.map(c => <option key={c.id} value={c.id}>{c.customer_code} — {c.name} ({[c.city, c.region].filter(Boolean).join(", ") || "Location not set"})</option>)}</select></label></div>
        <div className="form-divider"/>
        <div className="form-section-heading"><div><span className="form-section-number">02</span><div><h2>Order item</h2><p>The current selling price is copied into the booking; owner approval checks credit and available stock.</p></div></div></div>
        <div className="form-grid"><label className="field-label span-2">Product<select name="product_id" required defaultValue=""><option value="" disabled>Select a product…</option>{products.map(p => <option key={p.id} value={p.id}>{p.sku} — {p.name} · {money(p.unit_price)} / {p.unit}</option>)}</select></label><label className="field-label">Quantity<input name="quantity" type="number" step="0.001" min="0.001" placeholder="e.g. 24" required/></label></div>
        <div className="form-divider"/>
        <div className="form-section-heading"><div><span className="form-section-number">03</span><div><h2>Notes & internal context</h2><p>Optional instructions for the approver or dispatch team.</p></div></div></div>
        <label className="field-label">Order notes<textarea name="notes" rows={4} maxLength={2000} placeholder="Delivery timing, special handling, reference number…"/></label>
        <div className="approval-callout"><ShieldCheck size={18}/><div><strong>Approval safeguards are active</strong><p>On approval, SupplyOS checks the customer's available credit and reserves the required inventory in a database transaction.</p></div></div>
        <div className="form-footer"><Link href="/bookings" className="button button-secondary">Cancel</Link><button className="button button-primary" type="submit">Create booking <ClipboardCheck size={16}/></button></div>
      </form>}
    </div>
  );
}
