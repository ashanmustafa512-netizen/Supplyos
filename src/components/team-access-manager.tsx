"use client";

import { useCallback, useEffect, useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";
import { BriefcaseBusiness, CheckCircle2, ClipboardList, Copy, LoaderCircle, MailPlus, RefreshCw, ShieldCheck, Users } from "lucide-react";

type TeamRole = "manager" | "staff";
type TeamUser = { user_id: string; email: string | null; full_name: string; role: string; created_at: string };

export function TeamAccessManager() {
  const [users, setUsers] = useState<TeamUser[]>([]);
  const [loadingUsers, setLoadingUsers] = useState(true);
  const [creating, setCreating] = useState(false);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [role, setRole] = useState<TeamRole>("staff");
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [copied, setCopied] = useState("");

  const loadUsers = useCallback(async () => {
    const supabase = createClient();
    const { data, error: invokeError } = await supabase.functions.invoke("manage-team-logins", {
      body: { action: "list" },
    });
    if (invokeError) {
      setError(invokeError.message || "Could not load team accounts.");
    } else if (data?.error) {
      setError(String(data.error));
    } else {
      setUsers(Array.isArray(data?.users) ? data.users as TeamUser[] : []);
      setError("");
    }
    setLoadingUsers(false);
  }, []);

  useEffect(() => { void loadUsers(); }, [loadUsers]);

  async function createLogin(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setSuccess("");
    setCreating(true);
    const supabase = createClient();
    const { data, error: invokeError } = await supabase.functions.invoke("manage-team-logins", {
      body: {
        action: "create",
        full_name: name.trim(),
        email: email.trim().toLowerCase(),
        password,
        role,
      },
    });
    setCreating(false);

    if (invokeError) {
      setError(invokeError.message || "Could not create this login.");
      return;
    }
    if (data?.error) {
      setError(String(data.error));
      return;
    }

    setSuccess(String(data?.message ?? "Team login created."));
    setName("");
    setEmail("");
    setPassword("");
    setRole("staff");
    await loadUsers();
  }

  async function copyEmail(value: string) {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(value);
      window.setTimeout(() => setCopied(""), 1800);
    } catch {
      setError("Email could not be copied. Select and copy it manually.");
    }
  }

  const managerCount = users.filter(user => user.role === "manager").length;
  const employeeCount = users.filter(user => user.role === "staff").length;

  return (
    <div className="page-stack">
      <div className="team-access-metrics">
        <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-blue"><Users size={17}/></span><span className="metric-trend">Team accounts</span></div><div className="metric-value">{users.length}</div><div className="metric-label">Separate logins in this workspace</div></div>
        <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-violet"><BriefcaseBusiness size={17}/></span><span className="metric-trend">Managers</span></div><div className="metric-value">{managerCount}</div><div className="metric-label">Manager app access</div></div>
        <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-green"><ClipboardList size={17}/></span><span className="metric-trend">Employees</span></div><div className="metric-value">{employeeCount}</div><div className="metric-label">Employee app access</div></div>
      </div>

      <section className="panel team-access-form-panel">
        <div className="panel-heading">
          <div><h2>Create a manager or employee login</h2><p>Every person gets their own email address and password. Their role is assigned to this factory workspace.</p></div>
          <span className="panel-heading-icon"><MailPlus size={17}/></span>
        </div>
        <form onSubmit={createLogin} className="team-access-form">
          <div className="form-grid form-grid-two">
            <label className="field-label">Full name<input value={name} onChange={event => setName(event.target.value)} placeholder="e.g. Ali Khan" autoComplete="name" minLength={2} maxLength={120} required/></label>
            <label className="field-label">Work email<input value={email} onChange={event => setEmail(event.target.value)} type="email" placeholder="person@company.com" autoComplete="email" maxLength={254} required/></label>
            <label className="field-label">App / role<select value={role} onChange={event => setRole(event.target.value as TeamRole)}><option value="staff">Employee</option><option value="manager">Manager</option></select><span className="field-hint">{role === "manager" ? "Bookings, stock & warehouse, sales/recovery." : "Create bookings from shop visits and view your own bookings."}</span></label>
            <label className="field-label">Temporary password<input value={password} onChange={event => setPassword(event.target.value)} type="password" placeholder="At least 12 characters" autoComplete="new-password" minLength={12} maxLength={128} required/><span className="field-hint">Set a unique password and share it with this person privately.</span></label>
          </div>
          {error && <div className="notice notice-error" role="alert">{error}</div>}
          {success && <div className="notice notice-success" role="status"><CheckCircle2 size={16}/>{success}</div>}
          <div className="team-access-form-footer"><p><ShieldCheck size={15}/> Only Owner/Admin can create accounts. Passwords are not stored in this app or shown again after creation.</p><button className="button button-primary" type="submit" disabled={creating}>{creating ? <LoaderCircle className="spin" size={16}/> : <MailPlus size={16}/>} {creating ? "Creating login…" : "Create separate login"}</button></div>
        </form>
      </section>

      <section className="panel">
        <div className="panel-heading"><div><h2>Accounts in this workspace</h2><p>Each email signs in with its own password and the app assigned below.</p></div><button className="button button-secondary button-small" type="button" onClick={() => { setLoadingUsers(true); void loadUsers(); }} disabled={loadingUsers}><RefreshCw size={14}/> Refresh</button></div>
        <div className="table-scroll">
          <table className="data-table team-access-table">
            <thead><tr><th>Team member</th><th>Login email</th><th>App access</th><th>Added</th><th/></tr></thead>
            <tbody>
              {users.map(user => <tr key={user.user_id}>
                <td><strong>{user.full_name || "Team member"}</strong></td>
                <td>{user.email || "Email unavailable"}</td>
                <td><span className={`team-role-chip ${user.role === "manager" ? "team-role-manager" : user.role === "staff" ? "team-role-employee" : "team-role-owner"}`}>{user.role === "staff" ? "Employee" : user.role === "admin" ? "Admin" : user.role.charAt(0).toUpperCase() + user.role.slice(1)}</span></td>
                <td>{user.created_at ? new Date(user.created_at).toLocaleDateString() : "—"}</td>
                <td>{user.email && <button type="button" className="team-copy-button" onClick={() => void copyEmail(user.email!)} aria-label={`Copy ${user.email}`}><Copy size={14}/>{copied === user.email ? "Copied" : "Copy email"}</button>}</td>
              </tr>)}
              {!loadingUsers && users.length === 0 && <tr><td colSpan={5}><div className="empty-table"><div className="empty-table-icon"><Users size={20}/></div><strong>No team accounts have been added yet</strong><p>Create the first Manager or Employee login above.</p></div></td></tr>}
              {loadingUsers && <tr><td colSpan={5}><span className="muted">Loading workspace accounts…</span></td></tr>}
            </tbody>
          </table>
        </div>
        <div className="team-access-note"><ShieldCheck size={15}/><span>Owner and Admin accounts remain protected. This screen cannot promote another person to Owner or Admin.</span></div>
      </section>
    </div>
  );
}
