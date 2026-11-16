import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeft, Store } from "lucide-react";
import { createBookingShop } from "@/app/(app)/bookings/actions";
import { requireWorkspaceRole } from "@/lib/server-auth";

export const metadata: Metadata = { title: "Add shop" };
type Params = Promise<{ error?: string }>;

export default async function NewBookingShopPage({ searchParams }: { searchParams: Params }) {
  const params = await searchParams;
  await requireWorkspaceRole(["owner", "admin", "manager"]);
  return <div className="page-stack narrow-page">
    <Link href="/bookings/new" className="back-link"><ArrowLeft size={16}/> Back to booking</Link>
    <div className="page-heading-row"><div><div className="eyebrow">BOOKING WORKFLOW / SHOP</div><h1>Add a shop</h1><p>Register the shop here so it can be selected on the booking form. There is no separate Customers tab.</p></div></div>
    {params.error && <div className="notice notice-error">{params.error}</div>}
    <form action={createBookingShop} className="panel booking-create-form">
      <div className="form-section-heading"><div><span className="form-section-number">01</span><div><h2>Shop details</h2><p>Enter the minimum details needed for order creation.</p></div></div></div>
      <div className="form-grid form-grid-two">
        <label className="field-label">Shop code<input name="customer_code" required maxLength={40} placeholder="e.g. SHOP-001"/></label>
        <label className="field-label">Shop name<input name="name" required maxLength={160} placeholder="Shop or retailer name"/></label>
        <label className="field-label">City<input name="city" maxLength={100} placeholder="City"/></label>
        <label className="field-label">Region<input name="region" maxLength={100} placeholder="Region / district"/></label>
        <label className="field-label">Phone<input name="phone" type="tel" maxLength={40} placeholder="Contact number"/></label>
        <label className="field-label">Credit limit (PKR)<input name="credit_limit" type="number" min="0" step="0.01" defaultValue="0" required/></label>
      </div>
      <div className="approval-callout"><Store size={18}/><div><strong>Owner approval remains in control</strong><p>The shop starts with a neutral reliability score. Booking approval checks the saved credit limit and outstanding balance.</p></div></div>
      <div className="form-footer"><Link href="/bookings/new" className="button button-secondary">Cancel</Link><button className="button button-primary" type="submit">Save shop <Store size={16}/></button></div>
    </form>
  </div>;
}
