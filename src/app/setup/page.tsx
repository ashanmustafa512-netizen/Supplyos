import Link from "next/link";
import { ArrowRight, Database, KeyRound, Terminal } from "lucide-react";

export default function SetupPage() {
  return (
    <main className="setup-screen">
      <div className="setup-card">
        <div className="brand-lockup"><div className="brand-mark">S</div><div><strong>SupplyOS</strong><span>Factory Operations</span></div></div>
        <div className="eyebrow">LOCAL SETUP</div>
        <h1>Connect your factory workspace.</h1>
        <p className="muted">This app uses a real Supabase project for authentication and operational data. Add your project keys to enable sign-in and the database.</p>
        <div className="setup-steps">
          <div className="setup-step"><div className="setup-step-icon"><Database size={18}/></div><div><strong>1. Create a Supabase project</strong><p>Open <a href="https://supabase.com/dashboard" target="_blank" rel="noreferrer">Supabase Dashboard</a> and create a project for SupplyOS.</p></div></div>
          <div className="setup-step"><div className="setup-step-icon"><Terminal size={18}/></div><div><strong>2. Add the environment file</strong><p>Copy <code>.env.example</code> to <code>.env.local</code> in the project root.</p></div></div>
          <div className="setup-step"><div className="setup-step-icon"><KeyRound size={18}/></div><div><strong>3. Add your API credentials</strong><p>Paste your Project URL and publishable key from Supabase Project Settings → API Keys.</p></div></div>
        </div>
        <div className="code-snippet"><span>NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co</span><span>NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...</span></div>
        <div className="setup-footer"><span>Then run the SQL migration in the included README.</span><Link href="/login" className="button button-primary">Go to sign in <ArrowRight size={16}/></Link></div>
      </div>
    </main>
  );
}
