import type { Metadata } from "next";
import { redirect } from "next/navigation";

export const metadata: Metadata = { title: "Routes" };

export default function RoutesPage() {
  redirect("/dashboard");
}
