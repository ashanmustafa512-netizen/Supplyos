import type { Metadata } from "next";
import { redirect } from "next/navigation";

export const metadata: Metadata = { title: "Driver tracking setup" };

export default function DriverTrackingSetupPage() {
  redirect("/dashboard");
}
