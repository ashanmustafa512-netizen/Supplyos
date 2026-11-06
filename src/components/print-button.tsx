"use client";
import { Printer } from "lucide-react";
export function PrintButton({ label = "Print" }: { label?: string }) {
  return <button className="button button-secondary button-small no-print" type="button" onClick={() => window.print()}><Printer size={14}/>{label}</button>;
}
