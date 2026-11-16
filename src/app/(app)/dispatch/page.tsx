import type { Metadata } from "next";
import { redirect } from "next/navigation";

export const metadata: Metadata = { title: "Dispatch" };

export default function DispatchPage() {
  redirect("/dashboard");
}
