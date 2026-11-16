"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useState } from "react";
import {
  Activity, Bell, Boxes, Building2, Calculator, ChevronDown, ChevronLeft,
  ClipboardCheck, Command, CreditCard, Factory, LayoutDashboard, LogOut,
  Menu, Plus, Wallet, type LucideIcon,
} from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { ThemeControl } from "@/components/theme-control";
import { ManagerShiftLocation } from "@/components/manager-shift-location";
import { normalizeRole } from "@/lib/access";

type ShellProps = { children: React.ReactNode; email: string; workspaceName: string; role: string };
type NavItem = { label: string; href: string; icon: LucideIcon; section: string; allowedRoles: string[] };

const navItems: NavItem[] = [
  { label: "Overview", href: "/dashboard", icon: LayoutDashboard, section: "WORKSPACE", allowedRoles: ["owner", "admin", "manager", "staff", "accountant"] },
  { label: "Booking approvals", href: "/bookings", icon: ClipboardCheck, section: "ORDERS", allowedRoles: ["owner", "admin"] },
  { label: "Bookings", href: "/bookings", icon: ClipboardCheck, section: "ORDERS", allowedRoles: ["manager"] },
  { label: "My bookings", href: "/bookings", icon: ClipboardCheck, section: "ORDERS", allowedRoles: ["staff"] },
  { label: "New booking", href: "/bookings/new", icon: Plus, section: "ORDERS", allowedRoles: ["owner", "admin", "manager", "staff"] },
  { label: "Team live location", href: "/team-location", icon: Activity, section: "TEAM", allowedRoles: ["owner", "admin"] },
  { label: "Stock & warehouse", href: "/inventory", icon: Boxes, section: "OPERATIONS", allowedRoles: ["owner", "admin", "manager"] },
  { label: "Accounting", href: "/accounting", icon: Calculator, section: "BUSINESS", allowedRoles: ["owner", "admin"] },
  { label: "Payroll", href: "/payroll", icon: Wallet, section: "BUSINESS", allowedRoles: ["owner", "admin", "accountant"] },
  { label: "Sales & recovery", href: "/sales", icon: CreditCard, section: "BUSINESS", allowedRoles: ["owner", "admin", "manager"] },
];

export function AppShell({ children, email, workspaceName, role }: ShellProps) {
  const pathname = usePathname();
  const router = useRouter();
  const [mobileOpen, setMobileOpen] = useState(false);
  const [profileOpen, setProfileOpen] = useState(false);
  const [notificationsOpen, setNotificationsOpen] = useState(false);
  const [signingOut, setSigningOut] = useState(false);
  const normalizedRole = normalizeRole(role);
  const sections = ["WORKSPACE", "ORDERS", "TEAM", "OPERATIONS", "BUSINESS"];

  async function signOut() {
    setSigningOut(true);
    const supabase = createClient();
    await supabase.auth.signOut();
    router.replace("/login");
    router.refresh();
  }

  return (
    <div className="app-frame">
      {mobileOpen && <button className="mobile-scrim" aria-label="Close navigation" onClick={() => setMobileOpen(false)} />}
      <aside className={`sidebar ${mobileOpen ? "sidebar-open" : ""}`}>
        <div className="sidebar-brand"><div className="brand-mark"><Factory size={19}/></div><div className="brand-text"><strong>SupplyOS</strong><span>FACTORY OPERATIONS</span></div><span className="sidebar-collapse" aria-hidden="true"><ChevronLeft size={16}/></span></div>
        <div className="workspace-switch"><div className="workspace-avatar"><Building2 size={16}/></div><div className="workspace-name"><strong>{workspaceName || "Factory workspace"}</strong><span>Production workspace</span></div><ChevronDown size={15}/></div>
        <nav className="side-nav" aria-label="Main navigation">
          {sections.map(section => {
            const items = navItems.filter(item => item.section === section && item.allowedRoles.includes(normalizedRole));
            if (!items.length) return null;
            return <div className="nav-section" key={section}><div className="nav-section-label">{section}</div>{items.map(item => {
              const active = pathname === item.href || (item.href !== "/dashboard" && item.href !== "/bookings" && pathname.startsWith(`${item.href}/`)) || (item.href === "/bookings" && pathname.startsWith("/bookings") && pathname !== "/bookings/new");
              const Icon = item.icon;
              return <Link key={`${item.href}-${item.label}`} href={item.href} onClick={() => setMobileOpen(false)} className={`nav-link ${active ? "nav-link-active" : ""}`}><Icon size={17} strokeWidth={active ? 2.2 : 1.8}/><span>{item.label}</span></Link>;
            })}</div>;
          })}
        </nav>
        <div className="sidebar-bottom"><div className="sidebar-health"><span className="health-dot"/><div><strong>Workspace connected</strong><span>Data sync is active</span></div><Activity size={16}/></div><div className="sidebar-user"><div className="user-avatar">{(email[0] || "U").toUpperCase()}</div><div className="user-identity"><strong>{email.split("@")[0]}</strong><span>{role || "Unassigned"}</span></div><div className="profile-wrap"><button className="icon-button user-menu-btn" aria-label="Account menu" onClick={() => setProfileOpen(!profileOpen)}><ChevronDown size={16}/></button>{profileOpen && <div className="profile-menu"><span className="profile-email">{email}</span><button onClick={signOut} disabled={signingOut}><LogOut size={15}/>{signingOut ? "Signing out…" : "Sign out"}</button></div>}</div></div></div>
      </aside>
      <div className="app-main">
        <header className="topbar"><div className="topbar-left"><button className="mobile-menu icon-button" aria-label="Open navigation" onClick={() => setMobileOpen(true)}><Menu size={19}/></button><div className="breadcrumbs"><span>Workspace</span><span className="breadcrumb-slash">/</span><strong>{navItems.find(item => item.href === pathname && item.allowedRoles.includes(normalizedRole))?.label || (pathname.split("/").filter(Boolean).at(-1) || "Overview").replace(/-/g, " ").replace(/\b\w/g, c => c.toUpperCase())}</strong></div></div><div className="topbar-right"><ThemeControl/><div className="live-status"><span className="health-dot"/> All systems normal</div><div className="notification-wrap"><button className="icon-button notification-button" aria-label="Notifications" aria-expanded={notificationsOpen} onClick={() => setNotificationsOpen(!notificationsOpen)}><Bell size={18}/><i/></button>{notificationsOpen && <div className="notification-popover"><strong>Workspace notifications</strong><p>Pending booking approvals and stock alerts are shown in <Link href="/dashboard" onClick={() => setNotificationsOpen(false)}>Action required</Link>.</p><button type="button" onClick={() => setNotificationsOpen(false)}>Close</button></div>}</div><div className="topbar-divider"/><div className="topbar-org"><div className="mini-org-mark"><Command size={15}/></div><span>{workspaceName || "My Workspace"}</span></div></div></header>
        <main className="page-content">{normalizedRole === "manager" && <ManagerShiftLocation/>}{children}</main>
        <footer className="app-footer"><span>SupplyOS <span className="footer-dot">·</span> Factory Operations</span><span>Built to keep your supply chain moving</span></footer>
      </div>
    </div>
  );
}
