import type { Metadata } from "next";
import { AuthForm } from "@/components/auth-form";
import { isSupabaseConfigured } from "@/lib/env";
import Link from "next/link";

export const metadata: Metadata = { title: "Sign in" };

export default function LoginPage() {
  return (
    <main className="auth-screen">
      <div className="auth-left">
        <div className="auth-brand"><div className="brand-mark">S</div><div><strong>SupplyOS</strong><span>Factory Operations Platform</span></div></div>
        <div className="auth-copy"><div className="eyebrow eyebrow-light">ONE CONNECTED WORKSPACE</div><h1>From factory floor to final delivery.</h1><p>Bring bookings, stock, dispatch, and financial operations into one clear view.</p><div className="auth-mini-stats"><div><strong>07</strong><span>connected modules</span></div><div><strong>01</strong><span>source of truth</span></div><div><strong>24/7</strong><span>operational visibility</span></div></div></div>
        <div className="auth-bottom">Designed for modern manufacturing and distribution teams.</div>
      </div>
      <div className="auth-right">
        <AuthForm configured={isSupabaseConfigured}/>
        <p className="auth-legal">By continuing, you agree to use your factory workspace responsibly.</p>
        {!isSupabaseConfigured && <p className="auth-inline-note">Supabase keys are missing. <Link href="/setup">Complete setup first.</Link></p>}
      </div>
    </main>
  );
}
