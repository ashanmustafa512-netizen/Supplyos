"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";
import {
  ArrowRight, Eye, EyeOff, LoaderCircle, LockKeyhole, Mail,
  Building2, UserRound, ShieldCheck, BriefcaseBusiness, ClipboardList,
} from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { normalizeRole } from "@/lib/access";

type Mode = "signin" | "signup";
type LoginRole = "owner" | "manager" | "employee";

const roleChoices: {
  value: LoginRole;
  label: string;
  description: string;
  icon: typeof ShieldCheck;
  allowedDatabaseRoles: string[];
  destination: string;
}[] = [
  {
    value: "owner",
    label: "Owner",
    description: "Company control",
    icon: ShieldCheck,
    allowedDatabaseRoles: ["owner", "admin"],
    destination: "/dashboard",
  },
  {
    value: "manager",
    label: "Manager",
    description: "Daily operations",
    icon: BriefcaseBusiness,
    allowedDatabaseRoles: ["manager"],
    destination: "/dashboard",
  },
  {
    value: "employee",
    label: "Employee",
    description: "Shop visits & orders",
    icon: ClipboardList,
    allowedDatabaseRoles: ["staff"],
    destination: "/bookings",
  },
];

function roleLabel(role: string) {
  if (role === "owner" || role === "admin") return "Owner";
  if (role === "manager") return "Manager";
  if (role === "staff" || role === "employee") return "Employee";
  if (role === "accountant") return "Accountant";
  return "unassigned";
}

export function AuthForm({ configured }: { configured: boolean }) {
  const [mode, setMode] = useState<Mode>("signin");
  const [selectedRole, setSelectedRole] = useState<LoginRole>("owner");
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
    const email = String(form.get("email") ?? "").trim().toLowerCase();
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
          setSuccess("Check your email to confirm your new Owner account. Your factory workspace will be initialized when you first sign in.");
        }
        return;
      }

      const selected = roleChoices.find(choice => choice.value === selectedRole);
      if (!selected) throw new Error("Choose the app you want to sign in to.");

      const { data: authData, error: authError } = await supabase.auth.signInWithPassword({ email, password });
      if (authError) throw authError;

      const userId = authData.user?.id ?? authData.session?.user.id;
      if (!userId) {
        await supabase.auth.signOut();
        throw new Error("Sign-in succeeded but the account identity could not be verified. Please try again.");
      }

      let { data: memberships, error: membershipError } = await supabase
        .from("memberships")
        .select("organization_id, role")
        .eq("user_id", userId)
        .order("created_at", { ascending: true })
        .limit(2);

      // A first-time owner account creates its own workspace. Staff and managers
      // must be provisioned by the company owner and cannot self-register as them.
      if (!membershipError && (!memberships || memberships.length === 0) && selectedRole === "owner") {
        const { error: workspaceError } = await supabase.rpc("ensure_my_workspace");
        if (!workspaceError) {
          const retry = await supabase
            .from("memberships")
            .select("organization_id, role")
            .eq("user_id", userId)
            .order("created_at", { ascending: true })
            .limit(2);
          memberships = retry.data;
          membershipError = retry.error;
        }
      }

      if (membershipError) {
        await supabase.auth.signOut();
        throw new Error("We couldn't verify this account's SupplyOS role. Please try again or contact your workspace owner.");
      }

      if (!memberships || memberships.length === 0) {
        await supabase.auth.signOut();
        throw new Error("This email has no SupplyOS role assigned yet. Ask your company owner to set up your account.");
      }

      if (memberships.length !== 1) {
        await supabase.auth.signOut();
        throw new Error("This account is linked to more than one workspace. Ask your administrator to resolve the workspace assignment before signing in.");
      }

      const actualRole = normalizeRole(memberships[0].role);
      if (!selected.allowedDatabaseRoles.includes(actualRole)) {
        await supabase.auth.signOut();
        throw new Error(`This email is registered as ${roleLabel(actualRole)}, not ${selected.label}. Choose the correct login type or use the ${selected.label.toLowerCase()} account's own email and password.`);
      }

      router.replace(selected.destination);
      router.refresh();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Something went wrong. Please try again.");
    } finally {
      setLoading(false);
    }
  }

  function switchMode(nextMode: Mode) {
    setMode(nextMode);
    setSelectedRole("owner");
    setError("");
    setSuccess("");
    setShowPassword(false);
  }

  return (
    <div className="auth-form-wrap">
      <div className="auth-form-heading">
        <div className="eyebrow">{mode === "signin" ? "SELECT YOUR SUPPLYOS APP" : "OWNER WORKSPACE SETUP"}</div>
        <h2>{mode === "signin" ? "Sign in to your workspace" : "Create your Owner account"}</h2>
        <p>{mode === "signin" ? "Each person signs in with their own work email and password." : "Create the company workspace first. Managers and employees use their own accounts."}</p>
      </div>

      {mode === "signin" && (
        <div className="auth-role-picker" role="group" aria-label="Choose which SupplyOS app to open">
          {roleChoices.map(choice => {
            const Icon = choice.icon;
            const active = selectedRole === choice.value;
            return (
              <button
                key={choice.value}
                type="button"
                className={`auth-role-choice ${active ? "auth-role-choice-active" : ""}`}
                aria-pressed={active}
                onClick={() => {
                  setSelectedRole(choice.value);
                  setError("");
                }}
              >
                <span className="auth-role-icon"><Icon size={17}/></span>
                <strong>{choice.label}</strong>
                <small>{choice.description}</small>
              </button>
            );
          })}
        </div>
      )}

      <form className="auth-form" onSubmit={handleSubmit}>
        {mode === "signup" && (
          <>
            <label className="field-label">Your name<div className="input-icon-wrap"><UserRound size={17}/><input name="fullName" placeholder="e.g. Ahsan Khan" autoComplete="name" required maxLength={120}/></div></label>
            <label className="field-label">Factory / company name<div className="input-icon-wrap"><Building2 size={17}/><input name="companyName" placeholder="e.g. Atlas Manufacturing" required maxLength={120}/></div></label>
          </>
        )}
        <label className="field-label">{mode === "signup" ? "Owner work email" : `${roleChoices.find(choice => choice.value === selectedRole)?.label ?? "Work"} email`}<div className="input-icon-wrap"><Mail size={17}/><input name="email" type="email" placeholder="you@company.com" autoComplete="email" required maxLength={254}/></div></label>
        <label className="field-label">Password<div className="input-icon-wrap"><LockKeyhole size={17}/><input name="password" type={showPassword ? "text" : "password"} placeholder={mode === "signup" ? "At least 8 characters" : "Enter this account's password"} autoComplete={mode === "signup" ? "new-password" : "current-password"} minLength={8} required/><button className="password-toggle" type="button" aria-label={showPassword ? "Hide password" : "Show password"} onClick={() => setShowPassword(!showPassword)}>{showPassword ? <EyeOff size={17}/> : <Eye size={17}/>}</button></div></label>
        {error && <div className="form-alert form-alert-error" role="alert">{error}</div>}
        {success && <div className="form-alert form-alert-success" role="status">{success}</div>}
        <button className="button button-primary auth-submit" type="submit" disabled={loading}>
          {loading ? <LoaderCircle className="spin" size={17}/> : null}
          {loading ? "Please wait…" : mode === "signin" ? `Continue as ${roleChoices.find(choice => choice.value === selectedRole)?.label}` : "Create Owner workspace"}
          {!loading && <ArrowRight size={17}/>}
        </button>
      </form>

      <div className="auth-switch">
        {mode === "signin" ? "Setting up a new factory?" : "Already have an account?"}
        <button type="button" onClick={() => switchMode(mode === "signin" ? "signup" : "signin")}>{mode === "signin" ? "Create Owner account" : "Sign in"}</button>
      </div>
      {mode === "signin" && <p className="auth-role-note">Managers and employees need separate accounts assigned to this factory by its Owner. The selected login type is checked against your account's actual role.</p>}
      <div className="auth-security"><LockKeyhole size={14}/><span>Separate credentials · Role verified by Supabase</span></div>
    </div>
  );
}
