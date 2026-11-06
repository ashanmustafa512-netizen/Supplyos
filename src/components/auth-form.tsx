"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";
import { ArrowRight, Eye, EyeOff, LoaderCircle, LockKeyhole, Mail, Building2, UserRound } from "lucide-react";
import { createClient } from "@/lib/supabase/client";

type Mode = "signin" | "signup";

export function AuthForm({ configured }: { configured: boolean }) {
  const [mode, setMode] = useState<Mode>("signin");
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const router = useRouter();

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setSuccess("");
    if (!configured) {
      setError("Add your Supabase URL and publishable key to .env.local, then restart the development server.");
      return;
    }
    const form = new FormData(event.currentTarget);
    const email = String(form.get("email") ?? "").trim();
    const password = String(form.get("password") ?? "");
    const fullName = String(form.get("fullName") ?? "").trim();
    const companyName = String(form.get("companyName") ?? "").trim();
    setLoading(true);
    try {
      const supabase = createClient();
      if (mode === "signup") {
        const { data, error: authError } = await supabase.auth.signUp({
          email,
          password,
          options: {
            data: { full_name: fullName, company_name: companyName },
            emailRedirectTo: `${window.location.origin}/dashboard`,
          },
        });
        if (authError) throw authError;
        if (data.session) {
          router.replace("/dashboard");
          router.refresh();
        } else {
          setSuccess("Check your email to confirm your account. Your factory workspace will be ready when you sign in.");
        }
      } else {
        const { error: authError } = await supabase.auth.signInWithPassword({ email, password });
        if (authError) throw authError;
        router.replace("/dashboard");
        router.refresh();
      }
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Something went wrong. Please try again.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="auth-form-wrap">
      <div className="auth-form-heading"><div className="eyebrow">YOUR OPERATIONS, IN SYNC</div><h2>{mode === "signin" ? "Welcome back" : "Create your workspace"}</h2><p>{mode === "signin" ? "Sign in to your factory operations dashboard." : "Set up a private workspace for your factory."}</p></div>
      <form className="auth-form" onSubmit={handleSubmit}>
        {mode === "signup" && <>
          <label className="field-label">Your name<div className="input-icon-wrap"><UserRound size={17}/><input name="fullName" placeholder="e.g. Ahsan Khan" autoComplete="name" required maxLength={120}/></div></label>
          <label className="field-label">Factory / company name<div className="input-icon-wrap"><Building2 size={17}/><input name="companyName" placeholder="e.g. Atlas Manufacturing" required maxLength={120}/></div></label>
        </>}
        <label className="field-label">Work email<div className="input-icon-wrap"><Mail size={17}/><input name="email" type="email" placeholder="you@company.com" autoComplete="email" required maxLength={254}/></div></label>
        <label className="field-label">Password<div className="input-icon-wrap"><LockKeyhole size={17}/><input name="password" type={showPassword ? "text" : "password"} placeholder={mode === "signup" ? "At least 8 characters" : "Enter your password"} autoComplete={mode === "signup" ? "new-password" : "current-password"} minLength={8} required/><button className="password-toggle" type="button" aria-label={showPassword ? "Hide password" : "Show password"} onClick={() => setShowPassword(!showPassword)}>{showPassword ? <EyeOff size={17}/> : <Eye size={17}/>}</button></div></label>
        {error && <div className="form-alert form-alert-error" role="alert">{error}</div>}
        {success && <div className="form-alert form-alert-success" role="status">{success}</div>}
        <button className="button button-primary auth-submit" type="submit" disabled={loading}>{loading ? <LoaderCircle className="spin" size={17}/> : null}{loading ? "Please wait…" : mode === "signin" ? "Sign in to SupplyOS" : "Create factory workspace"}{!loading && <ArrowRight size={17}/>}</button>
      </form>
      <div className="auth-switch">{mode === "signin" ? "New to SupplyOS?" : "Already have a workspace?"} <button type="button" onClick={() => { setMode(mode === "signin" ? "signup" : "signin"); setError(""); setSuccess(""); }}>{mode === "signin" ? "Create an account" : "Sign in instead"}</button></div>
      <div className="auth-security"><LockKeyhole size={14}/><span>Protected by Supabase Auth and database access policies</span></div>
    </div>
  );
}
